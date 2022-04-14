ruleset gossip {
  meta {
    name "Gossip Lab"
    description <<
		>>
    author "Kyle Storey"
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias subscription
    shares get_threshold_violation_count, get_threshold_violation_each, violation_state, get_sensorID, gossip_ledger, seenMap, TX_to_SensorID, gossip_to_spread, pickSomeTea, peers, peersSensorID, getSensorIDFromTX, getTXFromSensorID, seenForSensorID, TX_Map, SensorID_Map, schedule, heartbeat_period, gossip_state
  }

  global {

    schedule = function(){schedule:list()};

    heartbeat_period = function(){ent:heartbeat_period};

    gossip_state = function(){ent:gossip_state};
    violation_state = function(){ent:violation_state};

    default_heartbeat_period = 5; //seconds

    get_sensorID = function(){ent:sensorID};

    get_threshold_violation_count = function(){
      return ent:gossip_to_spread.keys().reduce(function(accumulator, key) {
        value = ent:gossip_to_spread[key]
        type = value.get(["type"])
        increment = type != "threshold" => null | value.get(["incrementor"])
        return type != "threshold" => accumulator | accumulator + increment
      }, 0)
    };

    get_threshold_violation_each = function(){
      return ent:gossip_to_spread.keys().reduce(function(accumulator, key) {
        value = ent:gossip_to_spread[key]
        sensorID = value.get(["sensorID"])
        type = value.get(["type"])
        increment = type != "threshold" => null | value.get(["incrementor"])
        currentValue = accumulator.get([sensorID]).defaultsTo(0)
        return type != "threshold" => accumulator | accumulator.put(sensorID, currentValue + increment)
      }, {})
    };

    TX_Map = function() { ent:TX_Map }
    SensorID_Map = function() { ent:SensorID_Map }

    gossip_ledger = function(){ent:gossip_ledger};
    gossip_to_spread = function(){ent:gossip_to_spread};
    peers = function() {
      return subscription:established().filter(function (sub) {sub["Tx_role"] == "peer"})
    }
    peersSensorID = function() {
      peers().map(function(value) {
        return getSensorIDFromTX(value["Tx"])
      })
    }

    getSensorIDFromTX = function(TX) {
      return ent:TX_Map.get(TX)
    }
    getTXFromSensorID = function(SensorID) {
      return ent:SensorID_Map.get(SensorID)
    }
    TX_to_SensorID = function() {
      return peers().reduce(function(accumulator, value) {
         sensorID = wrangler:picoQuery(value["Tx"],"gossip","get_sensorID",{}).klog("SENSOR ID:")
         return accumulator.put(value["Tx"], sensorID)
      }, {})
    }
    SensorID_to_TX = function() {
      return peers().reduce(function(accumulator, value) {
         sensorID = wrangler:picoQuery(value["Tx"],"gossip","get_sensorID",{}).klog("SENSOR ID:")
         return accumulator.put(sensorID, value["Tx"])
      }, {})
    }

    seenForSensorID = function(sensorID) {
      //Gets the largest number for which we have all messages less then that number
      messageNumbers = ent:gossip_to_spread.keys().map(function(messageID) {
        sensorQ = messageID.split(":")[0]
        newNum = messageID.split(":")[1].decode()
        return sensorQ == sensorID => newNum | 0
      }, 0)
      return messageNumbers.sort("numeric").reduce(function(accumulator, value) {
        value == accumulator + 1 => value | accumulator
      }, 0)
    }

    pickSomeTea = function(d){
      depth = d.defaultsTo(0)
      theTea = ent:gossip_ledger
      peerID = randomChoice(theTea.keys().filter(function(value){value != ent:sensorID}))
      peer = theTea[peerID]
      target = randomChoice(peer.keys())
      messageID = target + ":" + (peer[target]+1)
      gossip = ent:gossip_to_spread[messageID]
      return gossip == null => (depth < 10 => pickSomeTea(depth+1) | null) | {
        "peer": peerID,
        "gossip": gossip,
        "maxNum": peer[target]+1,
      }
    }

    randomChoice = function(list) {
      index = random:integer(list.length()-1)
      return list[index]
    }

    seenMap = function() {
      //Gets the largest number for which we have all messages less then that number
      ledgerIDs = ent:gossip_ledger.keys()
      knownSensorIDs = ledgerIDs.reduce(function(accumulator, key) {
        value = ent:gossip_ledger[key]
        return value.keys().reduce(function(a, sensorID) {
          return a.put(sensorID, true) 
        }, accumulator)
      }, {}).keys()
      return knownSensorIDs.reduce(function(accumulator, sensorID) {
        return accumulator.put([sensorID], seenForSensorID(sensorID))
      }, {})
    }
  }

  rule update_sensorID_map {
    select when gossip update_maps
    always {
      ent:TX_Map := TX_to_SensorID() 
      ent:SensorID_Map := SensorID_to_TX() 
      ent:gossip_ledger := ent:SensorID_Map.keys().reduce(function(accumulator, sensorID) {
        seenMap = ent:SensorID_Map.keys().reduce(function(seen, key){
          currentValue = ent:gossip_ledger.get([sensorID, key]).defaultsTo(0)
          return sensorID == key => seen | seen.put([key], currentValue)
        }, {})
        currentValue = ent:gossip_ledger.get([ent:sensorID, sensorID]).defaultsTo(0)
        return accumulator.put([sensorID], seenMap.put([ent:sensorID], currentValue))
      }, ent:gossip_ledger).klog("NEW GOSSIP LEDGER")
    }
  }

  rule set_gossip_operation {
    select when gossip new_state
    if(event:attrs{"pause"}) then noop();
    fired {
      ent:gossip_state := "paused";
    } else {
      ent:gossip_state := "running";
    }
  }

  rule set_period {
    select when gossip new_heartbeat_period
    pre {
      period = event:attrs{"heartbeat_period"}
      lastSched = schedule:list().reduce(function(accumulator, value) {
        return value["event"]["name"] == "spill_the_tea" => value | accumulator
      }).klog("LAST SCHED:")
    }
    schedule:remove(lastSched["id"]);
    always {
      schedule gossip event "spill_the_tea" repeat << */#{period} * * * * * >>  attributes { }
      ent:heartbeat_period := period
      .klog("Heartbeat period: "); // in seconds

    }
  }

	rule gossip_about_my_temperatures {
		select when wovyn new_temperature_reading
		pre {
			gossip_to_spread = ent:gossip_to_spread.defaultsTo({})
			//.klog("GOSSIP")
			temperature = event:attrs{"genericThing"}["data"]["temperature"][0]["temperatureF"]
			.klog("TEMP")
			time = event:time
			.klog("TIME")
      sensorID = ent:sensorID.defaultsTo("BLANK_ID")
      messageCount = ent:messageCount.defaultsTo(0)
      messageID = sensorID + ":" + messageCount
      new_gossip = {"messageID": messageID, "sensorID": sensorID, "temperature": temperature, "time": time}
			.klog("RESULT")
		}
    always {
      ent:messageCount := messageCount + 1
      raise gossip event "new_gossip_from_peer"
        attributes {
          "messageID": messageID,
          "sensorID": sensorID,
          "type": "temperature",
          "temperature": temperature,
          "time": time,
          "sourceID": sensorID,
        }
    }

	}
	rule gossip_about_threshold_violation {
		select when wovyn threshold_violation
		pre {
			time = event:time
			.klog("TIME")
      sensorID = ent:sensorID.defaultsTo("BLANK_ID")
      messageCount = ent:messageCount.defaultsTo(0)
      messageID = sensorID + ":" + messageCount
		}
    if (ent:violation_state != 1) then noop() //don't send a decrement if we sent a decrement last
    fired {
      ent:violation_state := 1
      ent:messageCount := messageCount + 1
      raise gossip event "new_gossip_from_peer"
        attributes {
          "messageID": messageID,
          "sensorID": sensorID,
          "type": "threshold",
          "incrementor": 1,
          "time": time,
          "sourceID": sensorID,
        }
    }
	}

	rule gossip_about_threshold_ok {
		select when wovyn threshold_ok
		pre {
			time = event:time
			.klog("TIME")
      sensorID = ent:sensorID.defaultsTo("BLANK_ID")
      messageCount = ent:messageCount.defaultsTo(0)
      messageID = sensorID + ":" + messageCount
		}
    if (ent:violation_state != -1) then noop() //don't send a decrement if we sent a decrement last
    fired {
      ent:violation_state := -1
      ent:messageCount := messageCount + 1
      raise gossip event "new_gossip_from_peer"
        attributes {
          "messageID": messageID,
          "sensorID": sensorID,
          "type": "threshold",
          "incrementor": -1,
          "time": time,
          "sourceID": sensorID,
        }
    }
	}

  rule save_gossip_from_peers {
		select when gossip new_gossip_from_peer
		pre {
      gossip_ledger = ent:gossip_ledger.defaultsTo({})
			gossip_to_spread = ent:gossip_to_spread.defaultsTo({})
			//.klog("GOSSIP")
      messageID = event:attrs{"messageID"}
      sequenceNum = messageID.split(":")[1].decode()
      sensorID = event:attrs{"sensorID"}
      temperature = event:attrs{"temperature"}
      incrementor = event:attrs{"incrementor"}
      type = event:attrs{"type"}
      time = event:attrs{"time"}
      new_gossip = type == "temperature" => {"type": type, "messageID": messageID, "sensorID": sensorID, "temperature": temperature, "time": time}
        | {"type": type, "messageID": messageID, "sensorID": sensorID, "incrementor": incrementor, "time": time}
      sourceID = event:attrs{"sourceID"}
			.klog("RESULT")
      lastNum = gossip_ledger.get([sourceID, sensorID]).defaultsTo(0)
      maxNum = lastNum + 1 == sequenceNum => sequenceNum | lastNum
      //If they sent us the next message in the sequence remember they have seen it otherwise we will wait for them to catch up with us with a "seen message"
		}
    if ent:gossip_state == "running" || sensorID == ent:sensorID then noop()
    fired {
      ent:gossip_to_spread := gossip_to_spread.put([messageID], new_gossip)
      ent:gossip_ledger := gossip_ledger.put([sourceID, sensorID], maxNum)
    }
  }

  rule save_seen_from_peers {
		select when gossip new_seen_from_peer
		pre {
      gossip_ledger = ent:gossip_ledger.defaultsTo({})
			gossip_to_spread = ent:gossip_to_spread.defaultsTo({})
      maxNum = event:attrs{"maxNum"}
      seen = event:attrs{"seen"}
			.klog("seen")
      sourceID = event:attrs{"sourceID"}
			.klog("sourceID")
		}
    if ent:gossip_state == "running" then noop()
    fired {
      ent:gossip_ledger := seen.keys().reduce(function(accumulator, key) {
        return accumulator.put([sourceID, key], seen.get(key))
      }, ent:gossip_ledger).klog("NEW GOSSIP LEDGER")
    }
  }

  rule gossip_when_there_is_tea {
    select when gossip spill_the_tea
    pre {
      tea = pickSomeTea()
      .klog("PICKED TEA:")
      tx = tea == null => null | getTXFromSensorID(tea["peer"])
      .klog("TX:")
      peer = tea == null => null | tea["peer"]
      .klog("PEER")
      sensorID = tea == null => null | tea.get(["gossip", "sensorID"])
      .klog("SensorID:")
      maxNum = tea == null => null | tea["maxNum"]
      .klog("MaxNum:")
      randomPeerID = randomChoice(peersSensorID())
      .klog("RANDOM PEER ID:")
      randomPeerTx = randomPeerID == null => null | getTXFromSensorID(randomPeerID)
      .klog("RANDOM PEER TX:")
      seenMessage = seenMap()
      .klog("SEEN MESSAGE")
      messageType = tea == null => null | tea.get(["gossip", "type"])
      messageID = tea == null => null | tea.get(["gossip", "messageID"])
      temperature = tea == null => null | tea.get(["gossip", "temperature"])
      incrementor = tea == null => null | tea.get(["gossip", "incrementor"])
      time = tea == null => null | tea.get(["gossip", "time"])
      teaMessage = messageType == "temperature" => {
        "type": messageType,
        "messageID": messageID,
        "sensorID": sensorID,
        "temperature": temperature,
        "time": time,
        "sourceID": ent:sensorID,
      } | {
        "type": messageType,
        "messageID": messageID,
        "sensorID": sensorID,
        "incrementor": incrementor,
        "time": time,
        "sourceID": ent:sensorID,
      }

      .klog("TEA MESSAGE")
      seenNotGossip = (tea == null || random:integer(5) == 0)
      .klog("SEEN NOT GOSSIP:") //randomly decide to send a seen or gossip message
      eci = seenNotGossip => randomPeerTx | tx
      eventToSend = seenNotGossip => 
        ({ "eci": eci,
          "eid": "Seen:" + ent:SensorID,
          "domain": "gossip", "type": "new_seen_from_peer",
          "attrs":
          {
            "seen": seenMessage,
            "sourceID": ent:sensorID,
          }
        })
      |
        ({ "eci": eci,
          "eid": tea.get(["gossip", "messageID"]),
          "domain": "gossip", "type": "new_gossip_from_peer",
          "attrs": teaMessage
        })
      
      .klog("SEEN MESSAGE:")
    }
    if (eci != null && ent:gossip_state == "running") then event:send(eventToSend)
    fired {
      ent:gossip_ledger := seenNotGossip => ent:gossip_ledger | ent:gossip_ledger.put([peer, sensorID], maxNum) //Remember they have this gossip now
    }
  }

  rule inialize_ruleset {
    select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
    pre {
      period = ent:heartbeat_period
               .defaultsTo(event:attrs{"heartbeat_period"} || default_heartbeat_period)
               .klog("Initilizing heartbeat period: "); // in seconds

    }
    send_directive("Initializing sensor pico");
    fired {
      ent:heartbeat_period := period if ent:heartbeat_period.isnull();
      ent:emitter_state := "running"if ent:emitter_state.isnull();

      schedule gossip event "spill_the_tea" repeat << */#{period} * * * * * >>  attributes { }
      raise gossip event "resetState"
    } 
  }

  rule reset_state {
    select when gossip resetState
    always {
      ent:messageCount := 1
      ent:gossip_state := "running"
      ent:gossip_to_spread := {}
      ent:sensorID := random:uuid()
      ent:gossip_ledger := {}.put([ent:sensorID, ent:sensorID], 0)
      ent:TX_Map := {}
      ent:SensorID_Map := {}
      ent:violation_state := -1
    }

  }

}
