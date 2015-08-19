git = require '../git'

gitAdd = (repo, {addAll}={}) ->
  console.debug 'Repo for file is at', repo.getWorkingDirectory()
  if not addAll
    file = repo.relativize(atom.workspace.getActiveTextEditor()?.getPath())
  else
    file = null

  git.add(repo, file: file)

module.exports = gitAdd
