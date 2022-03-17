ruleset sensor_profile {
  meta {
    name "Temperature Query Lab"
    description <<
		>>
    author "Kyle Storey"
    provides profile
    shares profile
  }
   
  global {
    profile = function() {
      profile = ent:profile
      profile.klog("Profile:")
    }
  }

  rule change_profile {
    select when sensor profile_updated
    pre {
			name = event:attrs{"name"}
			location = event:attrs{"location"}
			threshold = event:attrs{"threshold"}
			smsNumber = event:attrs{"notificationSMSNumber"}
    }
    always {
      ent:profile := {
        "name": name,
        "location": location,
        "threshold": threshold,
        "smsNumber": smsNumber,
      }
    }
  }
   
}
