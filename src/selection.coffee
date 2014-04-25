_     = require('lodash')
DOM   = require('./dom')
Leaf  = require('./leaf')
Range = require('./lib/range')


class Selection
  constructor: (@doc, @emitter) ->
    @document = @doc.root.ownerDocument
    @range = this.getRange()

  checkFocus: ->
    return @document.activeElement == @doc.root

  getRange: ->
    return null unless this.checkFocus()
    nativeRange = this._getNativeRange()
    return null unless nativeRange?
    start = this._positionToIndex(nativeRange.startContainer, nativeRange.startOffset)
    if nativeRange.endContainer != nativeRange.startContainer
      end = this._positionToIndex(nativeRange.endContainer, nativeRange.endOffset)
    else
      end = start - nativeRange.startOffset + nativeRange.endOffset
    return new Range(Math.min(start, end), Math.max(start, end))

  preserve: (fn) ->
    nativeRange = this._getNativeRange()
    if nativeRange? and this.checkFocus()
      [startNode, startOffset] = this._encodePosition(nativeRange.startContainer, nativeRange.startOffset)
      [endNode, endOffset] = this._encodePosition(nativeRange.endContainer, nativeRange.endOffset)
      fn()
      [startNode, startOffset] = this._decodePosition(startNode, startOffset)
      [endNode, endOffset] = this._decodePosition(endNode, endOffset)
      this._setNativeRange(startNode, startOffset, endNode, endOffset)
    else
      fn()

  setRange: (range, silent) ->
    return this._setNativeRange(null) unless range?
    [startNode, startOffset] = this._indexToPosition(range.start)
    if range.isCollapsed()
      [endNode, endOffset] = [startNode, startOffset]
    else
      [endNode, endOffset] = this._indexToPosition(range.end)
    this._setNativeRange(startNode, startOffset, endNode, endOffset)
    this.update(silent)

  shiftAfter: (index, length, fn) ->
    range = this.getRange()
    fn()
    if range?
      range.shift(index, length)
      this.setRange(range)

  update: (silent) ->
    range = this.getRange()
    emit = !silent and !Range.compare(range, @range)
    @range = range
    # Set range before emitting to prevent infinite loop if listeners call quill.getSelection()
    @emitter.emit(@emitter.constructor.events.SELECTION_CHANGE, range) if emit

  _decodePosition: (node, offset) ->
    if DOM.isElement(node)
      childIndex = _.indexOf(DOM.getChildNodes(node.parentNode), node)
      offset += childIndex
      node = node.parentNode
    return [node, offset]

  _encodePosition: (node, offset) ->
    while true
      if DOM.isTextNode(node) or node.tagName == DOM.DEFAULT_BREAK_TAG or DOM.EMBED_TAGS[node.tagName]?
        return [node, offset]
      else if offset < node.childNodes.length
        node = node.childNodes[offset]
        offset = 0
      else if node.childNodes.length == 0
        return [node, 0]
      else
        node = node.lastChild
        offset = node.childNodes.length + 1

  _getNativeSelection: ->
    # IE8 will always get null selection
    return if @document.getSelection? then @document.getSelection() else null

  _getNativeRange: ->
    selection = this._getNativeSelection()
    return if selection?.rangeCount > 0 then selection.getRangeAt(0) else null

  _indexToPosition: (index) ->
    return [@doc.root, 0] if @doc.lines.length == 0
    [line, lineOffset] = @doc.findLineAt(index)
    [leaf, offset] = line.findLeafAt(lineOffset)
    node = leaf.node
    node = node.firstChild if DOM.isTextNode(node.firstChild)
    return this._decodePosition(node, offset)

  _positionToIndex: (node, offset) ->
    [leafNode, offset] = this._encodePosition(node, offset)
    leafNode = leafNode.parentNode if DOM.isTextNode(leafNode)
    line = @doc.findLine(leafNode)
    # TODO move to linked list
    return 0 unless line?   # Occurs on empty document
    leaf = line.findLeaf(leafNode)
    leafOffset = 0
    while leaf.prev?
      leaf = leaf.prev
      leafOffset += leaf.length
    lineOffset = 0
    while line.prev?
      line = line.prev
      lineOffset += line.length
    return lineOffset + leafOffset + offset

  _setNativeRange: (startNode, startOffset, endNode, endOffset) ->
    selection = this._getNativeSelection()
    return unless selection
    selection.removeAllRanges()
    if startNode?
      @doc.root.focus()
      nativeRange = @document.createRange()
      nativeRange.setStart(startNode, startOffset)
      nativeRange.setEnd(endNode, endOffset)
      selection.addRange(nativeRange)
    else
      @doc.root.blur()


module.exports = Selection
