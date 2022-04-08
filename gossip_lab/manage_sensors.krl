ruleset manage_sensors {
  meta {
    name "Sensor Manager"
    author "Kyle Storey"
		use module com.twillio.sdk alias twillio
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias subscription
    use module sensor_profile
    shares sensorChildren, sensors, temperatures, passQuery, subscribed, sensorResponses
  }
   
  global {
    sensorResponses = function() {
      allKeys = ent:tempResponses.keys().sort("numeric").reverse()
      respondingKeys = allKeys.length() < 5 => allKeys | allKeys.slice(0, 4)
      responses = ent:tempResponses.filter(function(v,k){respondingKeys.any(function(val) {val == k})})
      return responses
    }
    subscribed = function() {
      subscription:established()
    }
    sensorChildren = function() {
      ent:sensorChildren.klog("sensorMap")
    }
    sensors = function() {
      return subscription:established().filter(function (sub) {sub["Tx_role"] == "sensor"})
    }
    temperatures = function() {
      return sensors().map(function(v,k) {
         return {"Tx": v["Tx"], "Temperatures": wrangler:picoQuery(v["Tx"],"temperature_store","temperatures",{})};
      })
    }
    passQuery = function(eci, domain, query) {
       return wrangler:picoQuery(eci,domain,query,{});
    }
    defaultTempThreshold = 75
    defaultNotificationNumber = "+18019897113"
  }

  rule collect_temperatures {
    select when sensor collectTemperatures
    foreach (sensors()) setting(sensor) 
    pre {
      correlationID = ent:nextCorrelationID.defaultsTo(0)
    }
    event:send(
      { "eci": sensor["Tx"], 
        "eid": "gather_temperatures", // can be anything, used for correlation
        "domain": "sensor", "type": "gatherTemperatures",
        "attrs": {
          "correlationID": correlationID, //unique id for this round of requests
          "Rx": sensor["Rx"], //eci to send response on
          "Tx": sensor["Tx"], //eci we sent to for convinience 
        }
      }
    )
    fired {
      ent:nextCorrelationID := correlationID + 1 on final
    }
  }

  rule handle_temp_response {
    select when sensor temperatureResponse
    pre {
      correlationID = event:attrs{"correlationID"}
      fromTx = event:attrs{"Tx"}
      responseData = ent:tempResponses.get(correlationID)
        .defaultsTo({}).put(fromTx, {"temperature": event:attrs{"temperature"}})
      responseRecord = responseData.put("respondingSensors", responseData.keys().length() - 1) //NOT SURE WHY THERE IS AN EXTRA KEY
    }
    always {
      ent:tempResponses := ent:tempResponses.defaultsTo({}).put(correlationID, responseRecord)
    }
  }

  rule passEvent {
    select when sensor passEvent
      pre{
        childEvent = event:attrs{"childEvent"}
      }
      event:send(childEvent)
  }

  rule clear {
    select when sensor clear
    foreach ent:sensorChildren.keys() setting(s)
    always {
      raise sensor event "unneeded_sensor"
        attributes { "name": s }
    }
  }

  rule clearGossip {
    select when sensor clearGossip
    foreach ent:sensorChildren.keys() setting(name)
    pre {
      tx_to_clear = ent:sensorChildren.get(name)["tx"]
    }
    if tx_to_clear != null then
      event:send(
        { "eci": tx_to_clear, 
          "eid": "gossip clear", // can be anything, used for correlation
          "domain": "gossip", "type": "resetState",
          "attrs": {}
        }
      )
  }

  rule updateGossipMaps {
    select when sensor updateGossip
    foreach ent:sensorChildren.keys() setting(name)
    pre {
      tx_to_clear = ent:sensorChildren.get(name)["tx"]
    }
    if tx_to_clear != null then
      event:send(
        { "eci": tx_to_clear, 
          "eid": "gossip update", // can be anything, used for correlation
          "domain": "gossip", "type": "update_maps",
          "attrs": {}
        }
      )
  }

  rule clearResponses {
    select when sensor clearResponses
    always {
      ent:tempResponses := {}
      ent:nextCorrelationID := 0
    }
  }

  rule subscribe_forein_sensor {
    select when sensor introduce_sensor
    pre {
      new_sensor_name = event:attrs{"name"}
      new_sensor_wellknown = event:attrs{"wellKnown_Rx"}
    }
    always {
      raise wrangler event "subscription"
        attributes {
          "Id": "FOREIGN_" + new_sensor_wellknown,
          "wellKnown_Tx": new_sensor_wellknown,
          "name": new_sensor_name,
          "channel_type": "sensordata",
          "Rx_role": "manager",
          "Tx_role": "sensor",
        };
    }
  }
  
  rule add_sensor {
    select when sensor new_sensor
    pre {
      new_sensor_name = event:attrs{"name"}
      exists = ent:sensorChildren && ent:sensorChildren.keys() >< new_sensor_name
    }
    if exists then
      send_directive("Sensor Creation Failed: A sensor with that name allready exists.", {"name":new_sensor_name})
    notfired {
      ent:sensorChildren := ent:sensorChildren.defaultsTo({}).put(new_sensor_name, {})
      raise wrangler event "new_child_request"
        attributes { "name": new_sensor_name, "backgroundColor": "#ff69b4", "isNewSensor": true }
    }
  }

  rule record_tx {
    select when wrangler subscription_added
    pre {
      new_sensor_name = event:attrs{"name"}
      tx_eci = event:attrs{"Tx"}
      newRecord = ent:sensorChildren[new_sensor_name].defaultsTo({}).put("tx", tx_eci)
      exists = ent:sensorChildren.keys() >< new_sensor_name
    }
    if exists then noop()
    fired {
      ent:sensorChildren := ent:sensorChildren.defaultsTo({}).put(new_sensor_name, newRecord)
    }
  }

	rule record_eci {
		select when wrangler new_child_created
    pre {
      new_sensor_name = event:attrs{"name"}
      new_sensor_eci = event:attrs{"eci"}
      newRecord = ent:sensorChildren[new_sensor_name].defaultsTo({}).put("eci", new_sensor_eci)
      exists = ent:sensorChildren.keys() >< new_sensor_name
    }
    if exists then noop()
    fired {
      ent:sensorChildren := ent:sensorChildren.defaultsTo({}).put(new_sensor_name, newRecord)
    }
  }

	rule install_rulesets {
		select when wrangler new_child_created
    pre {
      new_sensor_name = event:attrs{"name"}
      new_sensor_eci = event:attrs{"eci"}
      isNewSensor = event:attrs{"isNewSensor"} == true
			new_map_entry = {"name": new_sensor_name, "eci": new_sensor_eci}
			absolutePath = "file:///Users/kylestorey/workspace/distributedSystems/DistributedSystems/gossip_lab/"
      wellknown_eci = wrangler:picoQuery(new_sensor_eci,"io.picolabs.subscription","wellKnown_Rx",{})["id"]
    }
		// "urls": [absolutePath + "sensor_profile.krl", absolutePath + "temperature_store.krl", absolutePath + "wovyn_base.krl", absolutePath + "wovyn.krl"],
    if isNewSensor then
			every {
				event:send(
					{ "eci": new_sensor_eci, 
						"eid": "install-twillio", // can be anything, used for correlation
						"domain": "wrangler", "type": "install_ruleset_request",
						"attrs": {
							"absoluteURL": absolutePath + "com.twillio.sdk.krl",
							"rid": "com.twillio.sdk",
							"config": {},
						}
					}
				)
				event:send(
					{ "eci": new_sensor_eci, 
						"eid": "install-profile", // can be anything, used for correlation
						"domain": "wrangler", "type": "install_ruleset_request",
						"attrs": {
							"absoluteURL": absolutePath + "sensor_profile.krl",
							"rid": "sensor_profile",
							"config": {},
						}
					}
				)
				event:send(
					{ "eci": new_sensor_eci, 
						"eid": "install-store", // can be anything, used for correlation
						"domain": "wrangler", "type": "install_ruleset_request",
						"attrs": {
							"absoluteURL": absolutePath + "temperature_store.krl",
							"rid": "temperature_store",
							"config": {},
						}
					}
				)
				event:send(
					{ "eci": new_sensor_eci, 
						"eid": "install-base", // can be anything, used for correlation
						"domain": "wrangler", "type": "install_ruleset_request",
						"attrs": {
							"absoluteURL": absolutePath + "wovyn_base.krl",
							"rid": "wovyn_base",
							"config": {},
						}
					}
				)
				event:send(
					{ "eci": new_sensor_eci, 
						"eid": "install-emitter", // can be anything, used for correlation
						"domain": "wrangler", "type": "install_ruleset_request",
						"attrs": {
							"absoluteURL": absolutePath + "io.picolabs.wovyn.emitter.krl",
							"rid": "io.picolabs.wovyn.emitter",
							"config": {},
						}
					}
				)
				event:send(
					{ "eci": new_sensor_eci, 
						"eid": "install-emitter", // can be anything, used for correlation
						"domain": "wrangler", "type": "install_ruleset_request",
						"attrs": {
							"absoluteURL": absolutePath + "gossip.krl",
							"rid": "gossip",
							"config": {},
						}
					}
				)
				event:send(
					{ "eci": new_sensor_eci, 
						"eid": "set-profile", // can be anything, used for correlation
						"domain": "sensor", "type": "profile_updated",
						"attrs": {
							"name": new_sensor_name,
							"location": "Virtual",
							"threshold": defaultTempThreshold,
							"smsNumber": defaultNotificationNumber,
						}
					}
				)
				event:send(
					{ "eci": new_sensor_eci, 
						"eid": "set-profile", // can be anything, used for correlation
						"domain": "sensor", "type": "profile_updated",
						"attrs": {
							"name": new_sensor_name,
							"location": "Virtual",
							"threshold": defaultTempThreshold,
							"smsNumber": defaultNotificationNumber,
						}
					}
				)
				send_directive("sensor_created", new_map_entry)
			}
    fired {
      raise wrangler event "subscription"
        attributes {
          "Id": "SUB_" + new_sensor_eci,
          "wellKnown_Tx": wellknown_eci,
          "name": new_sensor_name,
          "channel_type": "sensorData",
          "Rx_role": "manager",
          "Tx_role": "sensor",
        };
    }
  }

  rule delete_sensor {
    select when sensor unneeded_sensor
    pre {
      name = event:attrs{"name"}
      exists = ent:sensorChildren.keys() >< name
      eci_to_delete = ent:sensorChildren.get(name)["eci"]
      tx_to_delete = ent:sensorChildren.get(name)["tx"]
    }
    if exists && eci_to_delete then
      send_directive("deleting_section", {"name":name})
    fired {
      raise wrangler event "subscription_cancellation"
        attributes {"Tx": tx_to_delete};
      raise wrangler event "child_deletion_request"
        attributes {"eci": eci_to_delete};
      ent:sensorChildren := ent:sensorChildren.delete(name)
    }
  }
   
	rule threshold_notification { //handle threshold violation from subscriber
		select when sensordata threshold_violation
		pre {
			temperature = event:attrs["genericThing"]["data"]["temperature"][0]["temperatureF"]
      profile = sensor_profile:profile()
      phone_number = profile["smsNumber"] || defaultNotificationNumber
		}
    every {
			twillio:send_message(phone_number, "Temperature Above Threshold: " + temperature) setting(response)
			send_directive("say", {"result": "Temperature Above Threshold: " + temperature})
		}
	}
}
