{Disposable} = require 'atom'
{BufferedProcess} = require 'atom'
{$, $$$, View} = require 'atom-space-pen-views'

fs = require 'fs-plus'
Path = require 'flavored-path'

git = require '../git'

module.exports =
class RebaseInteractiveView extends View
  @content: ->
    @div class: 'git-plus-rebase-interactive', tabindex: -1, =>
      @table id: 'git-plus-commits', outlet: 'commitsListView'
      @div class: 'actions', =>
        @button class: 'btn btn-success apply-rebase', 'Apply Rebase'

  getURI: -> 'atom://git-plus:rebase-interactive'

  getTitle: -> 'git-plus: Log'

  initialize: ->
    @finished = false
    @numberOfCommitsToShow = 5

    @originalOrder = []

    @dragSrcEl = null
    @on 'dragstart', '.rebase-interactive-row', (event) =>
      @dragStart(event)
    @on 'dragover', '.rebase-interactive-row', (event) =>
      @dragOver(event)
    @on 'dragenter', '.rebase-interactive-row', (event) =>
      @dragEnter(event)
    @on 'dragleave', '.rebase-interactive-row', (event) =>
      @dragLeave(event)
    @on 'drop', '.rebase-interactive-row', (event) =>
      @dragDrop(event)
    @on 'dragend', '.rebase-interactive-row', (event) =>
      @dragEnd(event)
    @on 'click', '.apply-rebase', (event) =>
      @applyRebase(event)

  dragStart: (event) ->
    element = event.currentTarget
    element.style.opacity = 0.5

    @dragSrcEl = element
    origEvent = event.originalEvent
    origEvent.dataTransfer.effectAllowed = 'move'
    origEvent.dataTransfer.setData('text/plain', element.getAttribute('hash'))

  dragOver: (event) ->
    element = event.currentTarget
    event.preventDefault()
    console.log(event)
    event.originalEvent.dataTransfer.dropEffect = 'move'
    return false

  dragEnter: (event) ->
    element = event.currentTarget
    element.classList.add('drag-over')

  dragLeave: (event) ->
    element = event.currentTarget
    element.classList.remove('drag-over')

  dragDrop: (event) ->
    event.stopPropagation()
    element = event.currentTarget
    origEvent = event.originalEvent
    targetIndex = parseInt(element.getAttribute('index'))

    commitOrder = []
    @commitOrder.forEach((hash, index) ->
      droppedHash = origEvent.dataTransfer.getData('text/plain')
      console.log('INDEX', index, targetIndex)
      if index == targetIndex
        commitOrder.push(droppedHash)

      if hash != droppedHash
        commitOrder.push(hash)
    )

    @commitOrder = commitOrder
    @renderLog()
    return false

  dragEnd: (event) ->
    for el in @find('.rebase-interactive-row')
      el.style.opacity = 1.0
      el.classList.remove('drag-over')

  getLog: ->
    workingDir = '/home/stuart/Desktop/toygit/'
    repoPath = "#{workingDir}.git/"
    # repoPath = repo.getPath()
    # workingDir = repo.getWorkingDirectory()

    args = ['log', "--pretty=%h;|%H;|%aN;|%aE;|%s;|%ai_.;._", "-#{@numberOfCommitsToShow}"]
    args.push @currentFile if @onlyCurrentFile and @currentFile?
    git.cmd(args, cwd: workingDir)

  rebaseView: (repo) ->
    @getLog().then((data) =>
      @parseData(data)
    ).catch((err)->
      debugger
    )

  renderHeader: ->
    headerRow = $$$ ->
      @tr class: 'commit-header', =>
        @td 'Date'
        @td 'Message'
        @td class: 'hashShort', 'Short Hash'

    @commitsListView.append(headerRow)

  renderCommit: (commit, index) ->
    commitRow = $$$ ->
      @tr index: index, class: 'rebase-interactive-row', draggable: true, hash: "#{commit.hash}", =>
        @td class: 'message', "#{commit.message} (#{commit.hashShort})"
        @td class: 'actions', =>
          @span class: 'icon icon-pencil'

    @commitsListView.append(commitRow)

  renderLog: () ->
    @commitsListView.empty()
    @commitOrder.forEach((hash, index) => @renderCommit(@commits[hash], index))
    @skipCommits += @numberOfCommitsToShow

  applyRebase: () ->
    fromIndex = @originalOrder.findIndex((hash, idx) =>
      return hash != @commitOrder[idx]
    )
    rebaseFrom = @commitOrder.length - fromIndex
    rebaseCommits = @commitOrder.slice(fromIndex)
    # git checkout rebaseFrom
    # git checkout HEAD^

    workingDir = '/home/stuart/Desktop/toygit/'
    repoPath = "#{workingDir}.git/"
    # repoPath = repo.getPath()
    # workingDir = repo.getWorkingDirectory()
    # reorderOps = rebaseCommits.map((hash) -> git.cmd(['cherry-pick', hash], cwd: workingDir))

    console.log("git reset --hard HEAD~#{rebaseFrom}")
    rebaseCommits.forEach (hash) ->
      console.log("git cherry-pick #{hash}")
    debugger


    git.cmd(['reset', '--hard', "HEAD~#{rebaseFrom}"], cwd: workingDir).then(() =>
      rebaseCommits.reduce((cur, hash) ->
        cur.then () ->
          git.cmd(['cherry-pick', hash], cwd: workingDir)
      , Promise.resolve())
    ).then(() =>
      console.log('success')
    )

  parseData: (data) ->
    if data.length < 1
      @finished = true
      return

    separator = ';|'
    newline = '_.;._'
    data = data.substring(0, data.length - newline.length - 1)

    @commits = {}
    data.split(newline).reverse().forEach((line) =>
      if line.trim() isnt ''
        tmpData = line.trim().split(separator)
        @commits[tmpData[1]] = {
          hashShort: tmpData[0]
          hash: tmpData[1]
          author: tmpData[2]
          email: tmpData[3]
          message: tmpData[4]
          date: tmpData[5]
        }
    )

    @originalOrder = Object.keys(@commits)
    @commitOrder = Object.keys(@commits)
    @renderLog()
