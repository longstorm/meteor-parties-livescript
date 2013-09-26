# All Tomorrow's Parties -- server

Meteor.publish "directory", ->
  Meteor.users.find {}, fields: emails: 1, profile: 1

Meteor.publish "parties", -> Parties.find do
  $or: [{ "public": true }, { invited: this.userId }, { owner: this.userId }]
