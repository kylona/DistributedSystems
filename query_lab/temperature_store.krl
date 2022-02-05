ruleset temperature_store {
  meta {
    name "Temperature Query Lab"
    description <<
		>>
    author "Kyle Storey"
    provides temperatures, threshold_violations, inrange_temperatures
    shares temperatures, threshold_violations, inrange_temperatures
  }
   
  global {
    temperatures = function() {
      temp = ent:temperatures
      temp.klog("Temperatures:")
    }
    threshold_violations = function() {
      temp = ent:thresholdViolations
      temp.klog("Threshold Violations::")
    }
    inrange_temperatures = function() {
      inrange = ent:temperatures.filter(function(x){
        /* Tried doing this, but the timestamp is a few ticks apart
        ent:thresholdViolations.none(function(y){
          (x["temperature"] == y["temperature"]) && (x["time"] == y["time"])
        })
        */
        //I make it so only the temperatures have to match for them to be considered equal
        //I could just check if its above the threshold but this effectivly determines that threshold
        ent:thresholdViolations.none(function(y){
          (x["temperature"] == y["temperature"])
        })
      })
      inrange.klog("In Range Temperatures:")
    }
  }
   
	rule collect_temperatures {
		select when wovyn new_temperature_reading
		pre {
			temperature = event:attrs["genericThing"]["data"]["temperature"][0]["temperatureF"]
			.klog("TEMP")
			time = event:time
			.klog("TIME")
      result = {"temperature": temperature, "time": time}
			.klog("RESULT")
		}
    always {
      ent:temperatures := ent:temperatures == null => [result] | ent:temperatures.append(result)
    }
	}

	rule collect_threshold_notification {
		select when wovyn threshold_violation
		pre {
			temperature = event:attrs["genericThing"]["data"]["temperature"][0]["temperatureF"]
			.klog("TEMP")
			time = event:time
			.klog("TIME")
      result = {"temperature": temperature, "time": time}
			.klog("RESULT")
		}
    always {
      ent:thresholdViolations := ent:thresholdViolations == null => [result] | ent:thresholdViolations.append(result)
    }
	}

  rule clear_temperatures {
    select when sensor reading_reset
    always {
      ent:temperatures := []  
      ent:thresholdViolations := []  
    }
  }
   
}
