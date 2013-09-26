

# All Tomorrow's Parties -- data model
# Loaded on both the client and the server

error = (code, msg) -> throw new Meteor.Error code, msg

# ==============================================================================
# Parties

/*
  Each party is represented by a document in the Parties collection:
    owner: user id
    x, y: Number (screen coordinates in the interval [0, 1])
    title, description: String
    public: Boolean
    invited: Array of user id's that are invited (only if !public)
    rsvps: Array of objects like {user: userId, rsvp: "yes"} (or "no"/"maybe")
*/

Parties = new Meteor.Collection "parties"

Parties.allow do
  # no cowboy inserts -- use createParty method
  insert: (userId, party) -> false

  update: (userId, party, fields, modifier) ->
    return false if userId isnt party.owner

    allowed = <[ title description x y ]>
    if _.difference(fields, allowed).length
      return false # tried to write to forbidden field

    # A good improvement would be to validate the type of the new
    # value of the field (and if a string, the length.) In the
    # future Meteor will have a schema system to makes that easier.
    return true

  # You can only remove parties that you created and nobody is going to.
  remove: (userId, party) -> party.owner is userId and (attending party) is 0

attending = (party) ->
  (_.groupBy(party.rsvps, 'rsvp').yes or []).length

NonEmptyString = Match.Where (x) ->
  check x, String
  x.length isnt 0

var Coordinate = Match.Where (x) ->
  check x, Number
  x >= 0 and x <= 1

Meteor.methods do
  # options should include: title, description, x, y, public
  createParty: (opts) ->
    check opts,
      title: NonEmptyString
      description: NonEmptyString
      x: Coordinate
      y: Coordinate
      public: Match.Optional Boolean

    if opts.title.length > 100
      error 413, "Title too long"
    if opts.description.length > 1000
      error 413, "Description too long"
    if not this.userId
      error 403, "You must be logged in"

    return Parties.insert
      owner: this.userId
      x: opts.x
      y: opts.y
      title: opts.title
      description: opts.description
      public: not not opts.public
      invited: []
      rsvps: []

  invite: (partyId, userId) ->
    check partyId, String
    check userId, String
    party = Parties.findOne partyId

    if not party or party.owner isnt this.userId
      error 404, "No such party"
    if party.public
      error 400, "That party is public. No need to invite people."

    if userId isnt party.owner and not _.contains(party.invited, userId)
      Parties.update partyId, $addToSet: invited: userId

      from = contactEmail Meteor.users.findOne this.userId
      to = contactEmail Meteor.users.findOne userId
      if Meteor.isServer and to
        # This code only runs on the server. If you didn't want clients
        # to be able to see it, you could move it to a separate file.
        Email.send do
          from: "noreply@example.com"
          to: to
          replyTo: from or void
          subject: "PARTY: #{party.title}"
          text: "Hey, I just invited you to #{party.title} on All Tomorrow's
                 Parties.\n\nCome check it out: #{Meteor.absoluteUrl()}\n"

  rsvp: (partyId, rsvp) ->
    check partyId, String
    check rsvp, String
    if not this.userId
      error 403, "You must be logged in to RSVP"
    if not _.contains(['yes', 'no', 'maybe'], rsvp)
      error 400, "Invalid RSVP"
    var party = Parties.findOne partyId
    if not party
      throw new Meteor.Error(404, "No such party")
    if (! party.public && party.owner !== this.userId &&
        !_.contains(party.invited, this.userId))
      # private, but let's not tell this to the user
      throw new Meteor.Error(403, "No such party")

    var rsvpIndex = _.indexOf(_.pluck(party.rsvps, 'user'), this.userId)
    if (rsvpIndex !== -1) {
      # update existing rsvp entry

      if (Meteor.isServer) {
        # update the appropriate rsvp entry with $
        Parties.update(
          {_id: partyId, "rsvps.user": this.userId},
          {$set: {"rsvps.$.rsvp": rsvp}})
      } else {
        # minimongo doesn't yet support $ in modifier. as a temporary
        # workaround, make a modifier that uses an index. this is
        # safe on the client since there's only one thread.
        var modifier = {$set: {}}
        modifier.$set["rsvps." + rsvpIndex + ".rsvp"] = rsvp
        Parties.update(partyId, modifier)
      }

      # Possible improvement: send email to the other people that are
      # coming to the party.
    } else {
      # add new rsvp entry
      Parties.update(partyId,
                     {$push: {rsvps: {user: this.userId, rsvp: rsvp}}})
    }
  }
})

#===============================================================================
# Users

displayName = function (user) {
  if (user.profile && user.profile.name)
    return user.profile.name
  return user.emails[0].address
}

var contactEmail = function (user) {
  if (user.emails && user.emails.length)
    return user.emails[0].address
  if (user.services && user.services.facebook && user.services.facebook.email)
    return user.services.facebook.email
  return null
}
