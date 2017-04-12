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
      @div class: 'rebase-actions', =>
        @button class: 'btn btn-success apply-rebase', 'Apply Rebase'
        @button class: 'btn btn-default reset-rebase', 'Reset'

  getURI: -> 'atom://git-plus:rebase-interactive'

  getTitle: -> 'git-plus: Log'

  initialize: ->
    @finished = false
    @numberOfCommitsToShow = 10

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
    @on 'click', '.reset-rebase', (event) =>
      @reset(event)
    @on 'click', '.skip-commit', (event) =>
      @handleSkip(event)
    @on 'click', '.fixup-commit', (event) =>
      @handleFixup(event)
    @on 'click', '.reword-commit', (event) =>
      @handleReword(event)

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
    @commitOrder.forEach((hash, index) =>
      droppedHash = origEvent.dataTransfer.getData('text/plain')
      if index == targetIndex
        commitOrder.push(droppedHash)
        @commits[droppedHash].moved = true

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

  handleSkip: (event) ->
    element = event.currentTarget
    hash = element.getAttribute('hash')
    @commits[hash].skipped = !@commits[hash].skipped
    @renderLog()

  handleFixup: (event) ->
    element = event.currentTarget
    hash = element.getAttribute('hash')
    @commits[hash].fixup = !@commits[hash].fixup
    @renderLog()

  handleReword: (event) ->
    element = event.currentTarget
    hash = element.getAttribute('hash')
    @commits[hash].reword = true
    @renderLog()

  reset: (event) ->
    @rebaseView(@repo)

  getLog: ->
    repoPath = @repo.getPath()
    workingDir = @repo.getWorkingDirectory()

    args = ['log', "--pretty=%h;|%H;|%aN;|%aE;|%s;|%ai_.;._", "-#{@numberOfCommitsToShow}"]
    args.push @currentFile if @onlyCurrentFile and @currentFile?
    git.cmd(args, cwd: workingDir)

  rebaseView: (repo) ->
    @repo = repo
    @getLog().then((data) =>
      @parseData(data)
    ).catch((err)->
      debugger
    )

  renderCommit: (commit, index) ->
    classes = 'rebase-interactive-row'
    branchClass = 'icon icon-primitive-dot'

    if commit.moved
      classes += ' moved'

    if commit.skipped
      classes += ' skipped'
      branchClass = ''

    if commit.fixup
      classes += ' fixup'
      branchClass = ' icon icon-arrow-up'

    commitRow = $$$ ->
      @tr index: index, class: classes, draggable: true, hash: "#{commit.hash}", =>
        @td class: 'branch', =>
          @span class: branchClass
        @td class: 'message', "#{commit.message} (#{commit.hashShort})"
        @td class: 'actions', =>
          @button class: 'icon icon-pencil reword-commit', title: 'Reword', hash: "#{commit.hash}"
          @button class: 'icon icon-trashcan skip-commit', title: 'Skip', hash: "#{commit.hash}"
          @button class: 'icon icon-arrow-up fixup-commit', title: 'Fix-up', hash: "#{commit.hash}"

    @commitsListView.append(commitRow)

  renderLog: () ->
    @commitsListView.empty()
    @commitOrder.forEach((hash, index) => @renderCommit(@commits[hash], index))
    @skipCommits += @numberOfCommitsToShow

  applyRebase: () ->
    indexes = []
    indexes.push(@originalOrder.findIndex((hash, idx) =>
      return hash != @commitOrder[idx]
    ))
    indexes.push(@originalOrder.findIndex((hash) =>
      return @commits[hash].skipped == true
    ))

    fromIndex = indexes.sort().find((i) -> i > -1)
    if fromIndex is undefined
      return

    rebaseFrom = @commitOrder.length - fromIndex

    # Skip Commits
    rebaseCommits = @commitOrder.slice(fromIndex).filter((hash) =>
      return @commits[hash].skipped != true
    ).map((hash) => @commits[hash])

    repoPath = @repo.getPath()
    workingDir = @repo.getWorkingDirectory()

    git.cmd(['reset', '--hard', "HEAD~#{rebaseFrom}"], cwd: workingDir).then(() =>
      @applyCommits(rebaseCommits, workingDir)
    ).then(() =>
      @rebaseView(@repo)
    )

  applyCommits: (rebaseCommits, workingDir) ->
    rebaseCommits.reduce((cur, commit) =>
      hash = commit.hash
      cur.then(() =>
        git.cmd(['cherry-pick', hash], cwd: workingDir).then(() =>
          @fixupCommit(commit, workingDir)
        )
      )
    , Promise.resolve())

  fixupCommit: (commit, workingDir) ->
    if commit.fixup
      sequence = [
        ['reset', '--soft', 'HEAD^'],
        ['commit', '--amend', '--no-edit']
      ]
      @applyGitSequence(sequence, workingDir)
    else
      Promise.resolve()

  applyGitSequence: (sequence, workingDir) ->
    sequence.reduce((cur, cmd) ->
      cur.then () ->
        git.cmd(cmd, cwd: workingDir)
    , Promise.resolve())

  rewordCommit: (hash, workingDir) ->
    # git commit --amend --file /tmp/git-plus-reword-hash.txt
    return

  parseData: (data) ->
    if data.length < 1
      @finished = true
      return

    separator = ';|'
    newline = '_.;._'
    data = data.substring(0, data.length - newline.length - 1)

    @commits = {}
    data.split(newline).reverse().forEach((line, index) =>
      if line.trim() isnt ''
        tmpData = line.trim().split(separator)
        @commits[tmpData[1]] = {
          hashShort: tmpData[0]
          hash: tmpData[1]
          author: tmpData[2]
          email: tmpData[3]
          message: tmpData[4]
          date: tmpData[5]
          originalIndex: index
          moved: false
          skipped: false
          fixup: false
        }
    )

    @originalOrder = Object.keys(@commits)
    @commitOrder = Object.keys(@commits)
    @renderLog()
