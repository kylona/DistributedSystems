ruleset wovyn_base {
  meta {
    name "Hello World"
    description <<
		>>
		use module com.twillio.sdk alias twillio
			with
				apiKey = meta:rulesetConfig{"apiKey"}
        token = meta:rulesetConfig{"token"}
    author "Kyle Storey"
  }
   
  global {
		temperature_threshold = 78;
		phone_number = "+18019897113"
  }
   
  rule process_heartbeat {
    select when wovyn heartbeat
		if (event:attrs["genericThing"].isnull() == false) then 
			send_directive("say", {"something": "GOT TEMP"})
    fired {
      raise wovyn event "new_temperature_reading" attributes event:attrs
    }
  }

	rule find_high_temps {
		select when wovyn new_temperature_reading
		pre {
			temperature = event:attrs["genericThing"]["data"]["temperature"][0]["temperatureF"]
			.klog("TEMP")
		}
		if (temperature > temperature_threshold) then noop()
		fired {
      raise wovyn event "threshold_violation" attributes event:attrs
    }
	}

	rule threshold_notification {
		select when wovyn threshold_violation
		pre {
			temperature = event:attrs["genericThing"]["data"]["temperature"][0]["temperatureF"]
		}
    every {
			twillio:send_message(phone_number, "Temperature Above Threshold: " + temperature) setting(response)
			send_directive("say", {"result": response})
		}
	}
   
}
