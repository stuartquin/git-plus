git = require './git'
GitBranch = require './models/git-branch'
GitCommit = require './models/git-commit'

service =
  getRepo: git.getRepo
  commit: GitCommit
  checkoutNewBranch: GitBranch.newBranch
  checkoutBranch: GitBranch.gitBranches

module.exports = Object.freeze(service)
