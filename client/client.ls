# All Tomorrow's Parties -- client

Meteor.subscribe "directory"
Meteor.subscribe "parties"

# If no party selected, select one.
Meteor.startup ->
  Deps.autorun ->
    if not Session.get "selected"
      party = Parties.findOne()
      Session.set "selected", party._id if party

# ==============================================================================
# Party details sidebar

_.extend Template.details,
  party: -> Parties.findOne Session.get "selected"
  anyParties: -> Parties.find().count() > 0
  creatorName: ->
    owner = Meteor.users.findOne @owner
    return "me" if owner._id is Meteor.userId()
    return displayName owner
  canRemove: -> @owner is Meteor.userId() and attending(this) is 0
  maybeChosen: (what) ->
    myRsvp = (_.find @rsvps, (r) -> r.user is Meteor.userId()) or {}
    if what ~= myRsvp.rsvp then "chosen btn-inverse" else ""

rsvp = (response) ->
  if response then Meteor.call "rsvp", Session.get("selected"), response
  return false

Template.details.events do
  'click .rsvp_yes':   ->   rsvp "yes"
  'click .rsvp_maybe': ->   rsvp "maybe"
  'click .rsvp_no':    ->   rsvp "no"
  'click .invite': ->
    openInviteDialog()
    return false
  'click .remove': ->
    Parties.remove @_id
    return false

# ==============================================================================
# Party attendance widget

  rsvpName = ->
    var user = Meteor.users.findOne(@user)
    return displayName(user)
  }

  outstandingInvitations = ->
    var party = Parties.findOne(@_id)
    return Meteor.users.find({$and: [
      {_id: {$in: party.invited}}, # they're invited
      {_id: {$nin: _.pluck(party.rsvps, 'user')}} # but haven't RSVP'd
    ]})
  }

  invitationName = ->
    return displayName(this)
  }

  rsvpIs = function (what) {
    return @rsvp === what
  }

  nobody = ->
    return ! @public && (@rsvps.length + @invited.length === 0)
  }

  canInvite = ->
    return ! @public && @owner === Meteor.userId()
  }

#######################################/
# Map display

# Use jquery to get the position clicked relative to the map element.
var coordsRelativeToElement = function (element, event) {
  var offset = $(element).offset()
  var x = event.pageX - offset.left
  var y = event.pageY - offset.top
  return { x: x, y: y }
}

Template.map.events
events({
  'mousedown circle, mousedown text': function (event, template) {
    Session.set("selected", event.currentTarget.id)
  },
  'dblclick .map': function (event, template) {
    if (! Meteor.userId()) # must be logged in to create events
      return
    var coords = coordsRelativeToElement(event.currentTarget, event)
    openCreateDialog(coords.x / 500, coords.y / 500)
  }
})

_.extend Template.map,
  rendered = ->
    var self = this
    self.node = self.find("svg")

    if (! self.handle) {
      self.handle = Deps.autorun(->
        var selected = Session.get('selected')
        var selectedParty = selected && Parties.findOne(selected)
        var radius = function (party) {
          return 10 + Math.sqrt(attending(party)) * 10
        }

        # Draw a circle for each party
        var updateCircles = function (group) {
          group.attr("id", function (party) { return party._id; })
          .attr("cx", function (party) { return party.x * 500; })
          .attr("cy", function (party) { return party.y * 500; })
          .attr("r", radius)
          .attr("class", function (party) {
            return party.public ? "public" : "private"
          })
          .style('opacity', function (party) {
            return selected === party._id ? 1 : 0.6
          })
        }

        var circles = d3.select(self.node).select(".circles").selectAll("circle")
          .data(Parties.find().fetch(), function (party) { return party._id; })

        updateCircles(circles.enter().append("circle"))
        updateCircles(circles.transition().duration(250).ease("cubic-out"))
        circles.exit().transition().duration(250).attr("r", 0).remove()

        # Label each with the current attendance count
        var updateLabels = function (group) {
          group.attr("id", function (party) { return party._id; })
          .text(function (party) {return attending(party) || '';})
          .attr("x", function (party) { return party.x * 500; })
          .attr("y", function (party) { return party.y * 500 + radius(party)/2 })
          .style('font-size', function (party) {
            return radius(party) * 1.25 + "px"
          })
        }

        var labels = d3.select(self.node).select(".labels").selectAll("text")
          .data(Parties.find().fetch(), function (party) { return party._id; })

        updateLabels(labels.enter().append("text"))
        updateLabels(labels.transition().duration(250).ease("cubic-out"))
        labels.exit().remove()

        # Draw a dashed circle around the currently selected party, if any
        var callout = d3.select(self.node).select("circle.callout")
          .transition().duration(250).ease("cubic-out")
        if selectedParty
          callout.attr("cx", that.x * 500)
          .attr("cy", that.y * 500)
          .attr("r", radius(that) + 10)
          .attr("class", "callout")
          .attr("display", '')
        else
          callout.attr("display", 'none')
      })
    }
  }

  destroyed = ->
    @handle && @handle.stop()
  }

#######################################/
# Create Party dialog

var openCreateDialog = function (x, y) {
  Session.set("createCoords", {x: x, y: y})
  Session.set("createError", null)
  Session.set("showCreateDialog", true)
}

Template.page.showCreateDialog = ->
  return Session.get("showCreateDialog")
}

Template.createDialog.events({
  'click .save': function (event, template) {
    title = template.find(".title").value
    description = template.find(".description").value
    is-public = ! template.find(".private").checked
    coords = Session.get("createCoords")

    if (title.length && description.length) {
      Meteor.call('createParty', {
        title: title,
        description: description,
        x: coords.x,
        y: coords.y,
        public: is-public
      }, function (error, party) {
        if (! error) {
          Session.set("selected", party)
          if (! is-public && Meteor.users.find().count() > 1)
            openInviteDialog()
        }
      })
      Session.set("showCreateDialog", false)
    } else {
      Session.set("createError",
                  "It needs a title and a description, or why bother?")
    }
  },

  'click .cancel': ->
    Session.set("showCreateDialog", false)
  }
})

Template.createDialog.error = ->
  return Session.get("createError")
}

#######################################/
# Invite dialog

var openInviteDialog = ->
  Session.set("showInviteDialog", true)
}

Template.page.showInviteDialog = ->
  return Session.get("showInviteDialog")
}

Template.inviteDialog.events({
  'click .invite': function (event, template) {
    Meteor.call('invite', Session.get("selected"), @_id)
  },
  'click .done': function (event, template) {
    Session.set("showInviteDialog", false)
    return false
  }
})

_.extend Template.inviteDialog,
  uninvited = ->
    var party = Parties.findOne(Session.get("selected"))
    if (! party)
      return []; # party hasn't loaded yet
    return Meteor.users.find({$nor: [{_id: {$in: party.invited}},
                                     {_id: party.owner}]})
  }

  displayName = ->
    return displayName(this)
  }
