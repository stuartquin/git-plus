git = require '../git'
RebaseInteractiveView = require '../views/rebase-interactive-view'
RebaseInteractiveViewURI = 'atom://git-plus:rebase-interactive'

module.exports = (repo, {onlyCurrentFile}={}) ->
  atom.workspace.addOpener (uri) ->
    return new RebaseInteractiveView if uri is RebaseInteractiveViewURI

  currentFile = repo.relativize(atom.workspace.getActiveTextEditor()?.getPath())
  atom.workspace.open(RebaseInteractiveViewURI).then (view) ->
    view.rebaseView(repo)
