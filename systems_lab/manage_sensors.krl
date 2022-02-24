ruleset manage_sensors {
  meta {
    name "Sensor Manager"
    author "Kyle Storey"
    use module io.picolabs.wrangler alias wrangler
    shares sensorList, sensors, temperatures, passQuery
  }
   
  global {
    sensorList = function() {
      ent:sensors.keys().klog("sensorMap")
    }
    sensors = function() {
      ent:sensors.klog("sensorMap")
    }
    temperatures = function() {
      return ent:sensors.map(function(v,k) {
         return wrangler:picoQuery(v,"temperature_store","temperatures",{});
      })
    }
    passQuery = function(eci, domain, query) {
       return wrangler:picoQuery(eci,domain,query,{});
    }
    defaultTempThreshold = 75
    defaultNotificationNumber = "+18019897113"
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
    foreach ent:sensors.keys() setting(s)
    always {
      raise sensor event "unneeded_sensor"
        attributes { "name": s }
    }
  }
  
  rule add_sensor {
    select when sensor new_sensor
    pre {
      new_sensor_name = event:attrs{"name"}
      exists = ent:sensors && ent:sensors.keys() >< new_sensor_name
    }
    if exists then
      send_directive("Sensor Creation Failed: A sensor with that name allready exists.", {"name":new_sensor_name})
    notfired {
      ent:sensors := ent:sensors.defaultsTo({}).put(new_sensor_name, null)
      raise wrangler event "new_child_request"
        attributes { "name": new_sensor_name, "backgroundColor": "#ff69b4", "isNewSensor": true }
    }
  }

	rule record_eci {
		select when wrangler new_child_created
    pre {
      new_sensor_name = event:attrs{"name"}
      new_sensor_eci = event:attrs{"eci"}
      isNewSensor = event:attrs{"isNewSensor"} == true
			new_map_entry = {"name": new_sensor_name, "eci": new_sensor_eci}
			absolutePath = "file:///Users/kylestorey/workspace/distributedSystems/DistributedSystems/systems_lab/"
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
      ent:sensors := ent:sensors.defaultsTo({}).put(new_sensor_name, new_sensor_eci)
    }
  }

  rule delete_sensor {
    select when sensor unneeded_sensor
    pre {
      name = event:attrs{"name"}
      exists = ent:sensors.keys() >< name
      eci_to_delete = ent:sensors.get(name)
    }
    if exists && eci_to_delete then
      send_directive("deleting_section", {"name":name})
    fired {
      raise wrangler event "child_deletion_request"
        attributes {"eci": eci_to_delete};
        ent:sensors := ent:sensors.delete(name)
    }
  }
   
}
