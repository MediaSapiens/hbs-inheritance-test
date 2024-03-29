###
Chaplin 1.0.0-pre.

Chaplin may be freely distributed under the MIT license.
For all details and documentation:
http://github.com/chaplinjs/chaplin
###

'use strict'

require.define
  'jquery': (require, exports, module) -> module.exports = $
  'underscore': (require, exports, module) -> module.exports = _
  'backbone': (require, exports, module) -> module.exports = Backbone

require.define 'chaplin/application': (exports, require, module) ->
  Backbone = require 'backbone'
  mediator = require 'chaplin/mediator'
  Dispatcher = require 'chaplin/dispatcher'
  Layout = require 'chaplin/views/layout'
  Router = require 'chaplin/lib/router'
  EventBroker = require 'chaplin/lib/event_broker'

  # The application bootstrapper
  # ----------------------------

  module.exports = class Application

    # Borrow the static extend method from Backbone
    @extend = Backbone.Model.extend

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    # The site title used in the document title
    title: ''

    # The application instantiates these three core modules
    dispatcher: null
    layout: null
    router: null

    initialize: ->

    initDispatcher: (options) ->
      @dispatcher = new Dispatcher options

    initLayout: (options = {}) ->
      options.title ?= @title
      @layout = new Layout options

    # Instantiate the dispatcher
    # --------------------------

    # Pass the function typically returned by routes.coffee
    initRouter: (routes, options) ->
      # Save the reference for testing introspection only.
      # Modules should communicate with each other via Pub/Sub.
      @router = new Router options

      # Register all routes declared in routes.coffee
      routes? @router.match

      # After registering the routes, start Backbone.history
      @router.startHistory()

    # Disposal
    # --------

    disposed: false

    dispose: ->
      return if @disposed

      properties = ['dispatcher', 'layout', 'router']
      for prop in properties when this[prop]?
        this[prop].dispose()
        delete this[prop]

      @disposed = true

      # You’re frozen when your heart’s not open
      Object.freeze? this

require.define 'chaplin/mediator': (exports, require, module) ->
  _ = require 'underscore'
  Backbone = require 'backbone'
  support = require 'chaplin/lib/support'
  utils = require 'chaplin/lib/utils'

  # Mediator
  # --------

  # The mediator is a simple object all others modules use to communicate
  # with each other. It implements the Publish/Subscribe pattern.
  #
  # Additionally, it holds objects which need to be shared between modules.
  # In this case, a `user` property is created for getting the user object
  # and a `setUser` method for setting the user.
  #
  # This module returns the singleton object. This is the
  # application-wide mediator you might load into modules
  # which need to talk to other modules using Publish/Subscribe.

  # Start with a simple object
  mediator = {}

  # Publish / Subscribe
  # -------------------

  # Mixin event methods from Backbone.Events,
  # create Publish/Subscribe aliases
  mediator.subscribe   = Backbone.Events.on
  mediator.unsubscribe = Backbone.Events.off
  mediator.publish     = Backbone.Events.trigger

  # The `on` method should not be used,
  # it is kept only for purpose of compatibility with Backbone.
  mediator.on = mediator.subscribe

  # Initialize an empty callback list so we might seal the mediator later
  mediator._callbacks = null

  # Make properties readonly
  utils.readonly mediator, 'subscribe', 'unsubscribe', 'publish', 'on'

  # Sealing the mediator
  # --------------------

  # After adding all needed properties, you should seal the mediator
  # using this method
  mediator.seal = ->
    # Prevent extensions and make all properties non-configurable
    if support.propertyDescriptors and Object.seal
      Object.seal mediator

  # Make the method readonly
  utils.readonly mediator, 'seal'

  # Return our creation
  module.exports = mediator

require.define 'chaplin/dispatcher': (exports, require, module) ->
  _ = require 'underscore'
  Backbone = require 'backbone'
  utils = require 'chaplin/lib/utils'
  EventBroker = require 'chaplin/lib/event_broker'

  module.exports = class Dispatcher

    # Borrow the static extend method from Backbone
    @extend = Backbone.Model.extend

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    # The previous controller name
    previousControllerName: null

    # The current controller, its name, main view and parameters
    currentControllerName: null
    currentController: null
    currentAction: null
    currentParams: null

    # The current URL
    url: null

    constructor: ->
      @initialize arguments...

    initialize: (options = {}) ->
      # Merge the options
      @settings = _(options).defaults
        controllerPath: 'controllers/'
        controllerSuffix: '_controller'

      # Listen to global events
      @subscribeEvent 'matchRoute', @matchRoute
      @subscribeEvent '!startupController', @startupController

    # Controller management
    # Starting and disposing controllers
    # ----------------------------------

    # Handler for the global matchRoute event
    matchRoute: (route, params) ->
      @startupController route.controller, route.action, params

    # Handler for the global !startupController event
    #
    # The standard flow is:
    #
    #   1. Test if it’s a new controller/action with new params
    #   1. Hide the old view
    #   2. Dispose the old controller
    #   3. Instantiate the new controller, call the controller action
    #   4. Show the new view
    #
    startupController: (controllerName, action = 'index', params = {}) ->
      # Set default flags

      # Whether to update the URL after controller startup
      # Default to true unless explicitly set to false
      if params.changeURL isnt false
        params.changeURL = true

      # Whether to force the controller startup even
      # when current and new controllers and params match
      # Default to false unless explicitly set to true
      if params.forceStartup isnt true
        params.forceStartup = false

      # Check if the desired controller is already active
      isSameController =
        not params.forceStartup and
        @currentControllerName is controllerName and
        @currentAction is action and
        # Deep parameters check is not nice but the simplest way for now
        (not @currentParams or _(params).isEqual(@currentParams))

      # Stop if it’s the same controller/action with the same params
      return if isSameController

      # Fetch the new controller, then go on
      handler = _(@controllerLoaded).bind(this, controllerName, action, params)
      @loadController controllerName, handler

    # Load the constructor for a given controller name.
    # The default implementation uses require() from a AMD module loader
    # like RequireJS to fetch the constructor.
    loadController: (controllerName, handler) ->
      controllerFileName = utils.underscorize(controllerName) + @settings.controllerSuffix
      path = @settings.controllerPath + controllerFileName
      if define?.amd
        require [path], handler
      else
        handler require path

    # Handler for the controller lazy-loading
    controllerLoaded: (controllerName, action, params, ControllerConstructor) ->

      # Shortcuts for the old controller
      currentControllerName = @currentControllerName or null
      currentController     = @currentController     or null

      # Dispose the current controller
      if currentController
        # Notify the rest of the world beforehand
        @publishEvent 'beforeControllerDispose', currentController
        # Passing the params and the new controller name
        currentController.dispose params, controllerName

      # Initialize the new controller
      # Passing the params and the old controller name
      controller = new ControllerConstructor params, currentControllerName

      # Call the specific controller action
      # Passing the params and the old controller name
      controller[action] params, currentControllerName

      # Stop if the action triggered a redirect
      return if controller.redirected

      # Save the new controller
      @previousControllerName = currentControllerName
      @currentControllerName = controllerName
      @currentController = controller
      @currentAction = action
      @currentParams = params

      @adjustURL controller, params

      # We're done! Spread the word!
      @publishEvent 'startupController',
        previousControllerName: @previousControllerName
        controller: @currentController
        controllerName: @currentControllerName
        params: @currentParams

    # Change the URL to the new controller using the router
    adjustURL: (controller, params) ->
      if params.path or params.path is ''
        # Just use the matched path
        url = params.path

      else if typeof controller.historyURL is 'function'
        # Use controller.historyURL to get the URL
        # If the property is a function, call it
        url = controller.historyURL params

      else if typeof controller.historyURL is 'string'
        # If the property is a string, read it
        url = controller.historyURL

      else
        throw new Error 'Dispatcher#adjustURL: controller for ' +
          "#{@currentControllerName} does not provide a historyURL"

      # Tell the router to actually change the current URL
      @publishEvent '!router:changeURL', url if params.changeURL

      # Save the URL
      @url = url

    # Disposal
    # --------

    disposed: false

    dispose: ->
      return if @disposed

      @unsubscribeAllEvents()

      @disposed = true

      # You’re frozen when your heart’s not open
      Object.freeze? this

require.define 'chaplin/controllers/controller': (exports, require, module) ->
  _ = require 'underscore'
  Backbone = require 'backbone'
  EventBroker = require 'chaplin/lib/event_broker'

  module.exports = class Controller

    # Borrow the static extend method from Backbone
    @extend = Backbone.Model.extend

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    view: null
    currentId: null

    # Internal flag which stores whether `redirectTo`
    # was called in the current action
    redirected: false

    # You should set a `title` property and a `historyURL` property or method
    # on the derived controller. Like this:
    # title: 'foo'
    # historyURL: 'foo'
    # historyURL: ->

    constructor: ->
      @initialize arguments...

    initialize: ->
      # Empty per default

    # Redirection
    # -----------

    redirectTo: (arg1, action, params) ->
      @redirected = true
      if arguments.length is 1
        # URL was passed, try to route it
        @publishEvent '!router:route', arg1, (routed) ->
          unless routed
            throw new Error 'Controller#redirectTo: no route matched'
      else
        # Assume controller and action names were passed
        @publishEvent '!startupController', arg1, action, params

    # Disposal
    # --------

    disposed: false

    dispose: ->
      return if @disposed

      # Dispose and delete all members which are disposable
      for own prop of this
        obj = this[prop]
        if obj and typeof obj.dispose is 'function'
          obj.dispose()
          delete this[prop]

      # Unbind handlers of global events
      @unsubscribeAllEvents()

      # Remove properties which are not disposable
      properties = ['currentId', 'redirected']
      delete this[prop] for prop in properties

      # Finished
      @disposed = true

      # You're frozen when your heart’s not open
      Object.freeze? this

require.define 'chaplin/models/collection': (exports, require, module) ->
  _ = require 'underscore'
  Backbone = require 'backbone'
  EventBroker = require 'chaplin/lib/event_broker'
  Model = require 'chaplin/models/model'

  # Abstract class which extends the standard Backbone collection
  # in order to add some functionality
  module.exports = class Collection extends Backbone.Collection

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    # Use the Chaplin model per default, not Backbone.Model
    model: Model

    # Mixin a Deferred
    initDeferred: ->
      _(this).extend $.Deferred()

    # Serializes collection
    serialize: ->
      for model in @models
        if model instanceof Model
          # Use optimized Chaplin serialization
          model.serialize()
        else
          # Fall back to unoptimized Backbone stuff
          model.toJSON()

    # Adds a collection atomically, i.e. throws no event until
    # all members have been added
    addAtomic: (models, options = {}) ->
      return unless models.length
      options.silent = true
      direction = if typeof options.at is 'number' then 'pop' else 'shift'
      while model = models[direction]()
        @add model, options
      @trigger 'reset'

    # Updates a collection with a list of models
    # Just like the reset method, but only adds new items and
    # removes items which are not in the new list.
    # Fires individual `add` and `remove` event instead of one `reset`.
    #
    # options:
    #   deep: Boolean flag to specify whether existing models
    #         should be updated with new values
    update: (models, options = {}) ->
      fingerPrint = @pluck('id').join()
      ids = _(models).pluck('id')
      newFingerPrint = ids.join()

      # Only remove if ID fingerprints differ
      if newFingerPrint isnt fingerPrint
        # Remove items which are not in the new list
        _ids = _(ids) # Underscore wrapper
        i = @models.length
        while i--
          model = @models[i]
          unless _ids.include model.id
            @remove model

      # Only add/update list if ID fingerprints differ
      # or update is deep (member attributes)
      if newFingerPrint isnt fingerPrint or options.deep
        # Add items which are not yet in the list
        for model, i in models
          preexistent = @get model.id
          if preexistent
            # Update existing model
            preexistent.set model if options.deep
          else
            # Insert new model
            @add model, at: i

      return

    # Disposal
    # --------

    disposed: false

    dispose: ->
      return if @disposed

      # Fire an event to notify associated views
      @trigger 'dispose', this

      # Empty the list silently, but do not dispose all models since
      # they might be referenced elsewhere
      @reset [], silent: true

      # Unbind all global event handlers
      @unsubscribeAllEvents()

      # Remove all event handlers on this module
      @off()

      # If the model is a Deferred, reject it
      # This does nothing if it was resolved before
      @reject?()

      # Remove model constructor reference, internal model lists
      # and event handlers
      properties = [
        'model',
        'models', '_byId', '_byCid',
        '_callbacks'
      ]
      delete this[prop] for prop in properties

      # Finished
      @disposed = true

      # You’re frozen when your heart’s not open
      Object.freeze? this

require.define 'chaplin/models/model': (exports, require, module) ->
  _ = require 'underscore'
  Backbone = require 'backbone'
  utils = require 'chaplin/lib/utils'
  EventBroker = require 'chaplin/lib/event_broker'

  module.exports = class Model extends Backbone.Model

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    # Mixin a Deferred
    initDeferred: ->
      _(this).extend $.Deferred()

    # This method is used to get the attributes for the view template
    # and might be overwritten by decorators which cannot create a
    # proper `attributes` getter due to ECMAScript 3 limits.
    getAttributes: ->
      @attributes

    # Private helper function for serializing attributes recursively,
    # creating objects which delegate to the original attributes
    # when a property needs to be overwritten.
    serializeAttributes = (model, attributes, modelStack) ->
      # Create a delegator on initial call
      unless modelStack
        delegator = utils.beget attributes
        modelStack = [model]
      else
        # Add model to stack
        modelStack.push model
      # Map model/collection to their attributes
      for key, value of attributes
        if value instanceof Backbone.Model
          # Don’t change the original attribute, create a property
          # on the delegator which shadows the original attribute
          delegator ?= utils.beget attributes
          delegator[key] = if value is model or value in modelStack
            # Nullify circular references
            null
          else
            # Serialize recursively
            serializeAttributes(
              value, value.getAttributes(), modelStack
            )
        else if value instanceof Backbone.Collection
          delegator ?= utils.beget attributes
          delegator[key] = for item in value.models
            serializeAttributes(
              item, item.getAttributes(), modelStack
            )

      # Remove model from stack
      modelStack.pop()
      # Return the delegator if it was created, otherwise the plain attributes
      delegator or attributes

    # Return an object which delegates to the attributes
    # (i.e. an object which has the attributes as prototype)
    # so primitive values might be added and altered safely.
    # Map models to their attributes, recursively.
    serialize: ->
      serializeAttributes this, @getAttributes()

    # Disposal
    # --------

    disposed: false

    dispose: ->
      return if @disposed

      # Fire an event to notify associated collections and views
      @trigger 'dispose', this

      # Unbind all global event handlers
      @unsubscribeAllEvents()

      # Remove all event handlers on this module
      @off()

      # If the model is a Deferred, reject it
      # This does nothing if it was resolved before
      @reject?()

      # Remove the collection reference, internal attribute hashes
      # and event handlers
      properties = [
        'collection',
        'attributes', 'changed'
        '_escapedAttributes', '_previousAttributes',
        '_silent', '_pending',
        '_callbacks'
      ]
      delete this[prop] for prop in properties

      # Finished
      @disposed = true

      # You’re frozen when your heart’s not open
      Object.freeze? this

require.define 'chaplin/views/layout': (exports, require, module) ->
  $ = require 'jquery'
  _ = require 'underscore'
  Backbone = require 'backbone'
  utils = require 'chaplin/lib/utils'
  EventBroker = require 'chaplin/lib/event_broker'

  module.exports = class Layout # This class does not extend View

    # Borrow the static extend method from Backbone
    @extend = Backbone.Model.extend

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    # The site title used in the document title.
    # This should be set in your app-specific Application class
    # and passed as an option
    title: ''

    # An hash to register events, like in Backbone.View
    # It is only meant for events that are app-wide
    # independent from any view
    events: {}

    # Register @el, @$el and @cid for delegating events
    el: document
    $el: $(document)
    cid: 'chaplin-layout'

    constructor: ->
      @initialize arguments...

    initialize: (options = {}) ->
      @title = options.title
      @settings = _(options).defaults
        titleTemplate: _.template("<%= subtitle %> \u2013 <%= title %>")
        openExternalToBlank: false
        routeLinks: 'a, .go-to'
        skipRouting: '.noscript'
        # Per default, jump to the top of the page
        scrollTo: [0, 0]

      @subscribeEvent 'beforeControllerDispose', @hideOldView
      @subscribeEvent 'startupController', @showNewView
      @subscribeEvent 'startupController', @adjustTitle

      # Set the app link routing
      if @settings.routeLinks
        @startLinkRouting()

      # Set app wide event handlers
      @delegateEvents()

    # Take (un)delegateEvents from Backbone
    # -------------------------------------
    delegateEvents: Backbone.View::delegateEvents
    undelegateEvents: Backbone.View::undelegateEvents

    # Controller startup and disposal
    # -------------------------------

    # Handler for the global beforeControllerDispose event
    hideOldView: (controller) ->
      # Reset the scroll position
      scrollTo = @settings.scrollTo
      if scrollTo
        window.scrollTo scrollTo[0], scrollTo[1]

      # Hide the current view
      view = controller.view
      if view
        view.$el.css 'display', 'none'

    # Handler for the global startupController event
    # Show the new view
    showNewView: (context) ->
      view = context.controller.view
      if view
        view.$el.css display: 'block', opacity: 1, visibility: 'visible'

    # Handler for the global startupController event
    # Change the document title to match the new controller
    # Get the title from the title property of the current controller
    adjustTitle: (context) ->
      title = @title or ''
      subtitle = context.controller.title or ''
      title = @settings.titleTemplate {title, subtitle}

      # Internet Explorer < 9 workaround
      setTimeout (-> document.title = title), 50

    # Automatic routing of internal links
    # -----------------------------------

    startLinkRouting: ->
      if @settings.routeLinks
        $(document).on 'click', @settings.routeLinks, @openLink

    stopLinkRouting: ->
      if @settings.routeLinks
        $(document).off 'click', @settings.routeLinks

    # Handle all clicks on A elements and try to route them internally
    openLink: (event) =>
      return if utils.modifierKeyPressed(event)

      el = event.currentTarget
      $el = $(el)
      isAnchor = el.nodeName is 'A'

      # Get the href and perform checks on it
      href = $el.attr('href') or $el.data('href') or null

      # Basic href checks
      return if href is null or href is undefined or
        # Technically an empty string is a valid relative URL
        # but it doesn’t make sense to route it.
        href is '' or
        # Exclude fragment links
        href.charAt(0) is '#'

      # Checks for A elements
      return if isAnchor and (
        # Exclude links marked as external
        $el.attr('target') is '_blank' or
        $el.attr('rel') is 'external' or
        # Exclude links to non-HTTP ressources
        el.protocol not in ['http:', 'https:', 'file:']
      )

      # Apply skipRouting option
      skipRouting = @settings.skipRouting
      type = typeof skipRouting
      return if type is 'function' and not skipRouting(href, el) or
        type is 'string' and $el.is skipRouting

      # Handle external links
      internal = not isAnchor or el.hostname in [location.hostname, '']
      unless internal
        if @settings.openExternalToBlank
          # Open external links normally in a new tab
          event.preventDefault()
          window.open el.href
        return

      if isAnchor
        # Get the path with query string
        path = el.pathname + el.search
        # Leading slash for IE8
        path = "/#{path}" if path.charAt(0) isnt '/'
      else
        path = href

      # Pass to the router, try to route the path internally
      @publishEvent '!router:route', path, (routed) ->
        # Prevent default handling if the URL could be routed
        if routed
          event.preventDefault()
        else unless isAnchor
          location.href = path
        return

      return

    # Disposal
    # --------

    disposed: false

    dispose: ->
      return if @disposed

      @stopLinkRouting()
      @unsubscribeAllEvents()
      @undelegateEvents()

      delete @title

      @disposed = true

      # You’re frozen when your heart’s not open
      Object.freeze? this

require.define 'chaplin/views/view': (exports, require, module) ->
  $ = require 'jquery'
  _ = require 'underscore'
  Backbone = require 'backbone'
  utils = require 'chaplin/lib/utils'
  EventBroker = require 'chaplin/lib/event_broker'
  Model = require 'chaplin/models/model'
  Collection = require 'chaplin/models/collection'

  module.exports = class View extends Backbone.View

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    # Automatic rendering
    # -------------------

    # Flag whether to render the view automatically on initialization.
    # As an alternative you might pass a `render` option to the constructor.
    autoRender: false

    # Automatic inserting into DOM
    # ----------------------------

    # View container element
    # Set this property in a derived class to specify the container element.
    # Normally this is a selector string but it might also be an element or
    # jQuery object.
    # The view is automatically inserted into the container when it’s rendered.
    # As an alternative you might pass a `container` option to the constructor.
    container: null

    # Method which is used for adding the view to the DOM
    # Like jQuery’s `html`, `prepend`, `append`, `after`, `before` etc.
    containerMethod: 'append'

    # Subviews
    # --------

    # List of subviews
    subviews: null
    subviewsByName: null

    # Method wrapping to enable `afterRender` and `afterInitialize`
    # -------------------------------------------------------------

    # Wrap a method in order to call the corresponding
    # `after-` method automatically
    wrapMethod: (name) ->
      instance = this
      # Enclose the original function
      func = instance[name]
      # Set a flag
      instance["#{name}IsWrapped"] = true
      # Create the wrapper method
      instance[name] = ->
        # Stop if the view was already disposed
        return false if @disposed
        # Call the original method
        func.apply instance, arguments
        # Call the corresponding `after-` method
        instance["after#{utils.upcase(name)}"] arguments...
        # Return the view
        instance

    constructor: ->
      # Wrap `initialize` so `afterInitialize` is called afterwards
      # Only wrap if there is an overring method, otherwise we
      # can call the `after-` method directly
      unless @initialize is View::initialize
        @wrapMethod 'initialize'

      # Wrap `render` so `afterRender` is called afterwards
      unless @render is View::render
        @wrapMethod 'render'
      else
        # Otherwise just bind the `render` method
        @render = _(@render).bind this

      # Call Backbone’s constructor
      super

    initialize: (options) ->
      # No super call here, Backbone’s `initialize` is a no-op

      # Copy some options to instance properties
      if options
        for prop in ['autoRender', 'container', 'containerMethod']
          if options[prop]?
            @[prop] = options[prop]

      # Initialize subviews
      @subviews = []
      @subviewsByName = {}

      # Listen for disposal of the model
      # If the model is disposed, automatically dispose the associated view
      if @model or @collection
        @modelBind 'dispose', @dispose

      # Call `afterInitialize` if `initialize` was not wrapped
      unless @initializeIsWrapped
        @afterInitialize()

    # This method is called after a specific `initialize` of a derived class
    afterInitialize: ->
      # Render automatically if set by options or instance property
      @render() if @autoRender

    # User input event handling
    # -------------------------

    # Event handling using event delegation
    # Register a handler for a specific event type
    # For the whole view:
    #   delegate(eventType, handler)
    #   e.g.
    #   @delegate('click', @clicked)
    # For an element in the passing a selector:
    #   delegate(eventType, selector, handler)
    #   e.g.
    #   @delegate('click', 'button.confirm', @confirm)
    delegate: (eventType, second, third) ->
      if typeof eventType isnt 'string'
        throw new TypeError 'View#delegate: first argument must be a string'

      if arguments.length is 2
        handler = second
      else if arguments.length is 3
        selector = second
        if typeof selector isnt 'string'
          throw new TypeError 'View#delegate: ' +
            'second argument must be a string'
        handler = third
      else
        throw new TypeError 'View#delegate: ' +
          'only two or three arguments are allowed'

      if typeof handler isnt 'function'
        throw new TypeError 'View#delegate: ' +
          'handler argument must be function'

      # Add an event namespace
      list = ("#{event}.delegate#{@cid}" for event in eventType.split(' '))
      events = list.join(' ')

      # Bind the handler to the view
      handler = _(handler).bind(this)

      if selector
        # Register handler
        @$el.on events, selector, handler
      else
        # Register handler
        @$el.on events, handler

      # Return the bound handler
      handler

    # Remove all handlers registered with @delegate

    undelegate: ->
      @$el.unbind ".delegate#{@cid}"

    # Model binding
    # The following implementation resembles EventBroker
    # --------------------------------------------------

    # Bind to a model event
    modelBind: (type, handler) ->
      if typeof type isnt 'string'
        throw new TypeError 'View#modelBind: ' +
          'type must be a string'
      if typeof handler isnt 'function'
        throw new TypeError 'View#modelBind: ' +
          'handler argument must be function'

      # Get model/collection reference
      modelOrCollection = @model or @collection
      unless modelOrCollection
        throw new TypeError 'View#modelBind: no model or collection set'

      # Ensure that a handler isn’t registered twice
      modelOrCollection.off type, handler, this

      # Register model handler, force context to the view
      modelOrCollection.on type, handler, this

    # Unbind from a model event

    modelUnbind: (type, handler) ->
      if typeof type isnt 'string'
        throw new TypeError 'View#modelUnbind: ' +
          'type argument must be a string'
      if typeof handler isnt 'function'
        throw new TypeError 'View#modelUnbind: ' +
          'handler argument must be a function'

      # Get model/collection reference
      modelOrCollection = @model or @collection
      return unless modelOrCollection

      # Remove model handler
      modelOrCollection.off type, handler

    # Unbind all recorded model event handlers
    modelUnbindAll: ->
      # Get model/collection reference
      modelOrCollection = @model or @collection
      return unless modelOrCollection

      # Remove all handlers with a context of this view
      modelOrCollection.off null, null, this

    # Setup a simple one-way model-view binding
    # Pass changed attribute values to specific elements in the view
    # For form controls, the value is changed, otherwise the element
    # text content is set to the model attribute value.
    # Example: @pass 'attribute', '.selector'
    pass: (attribute, selector) ->
      @modelBind "change:#{attribute}", (model, value) =>
        $el = @$(selector)
        if $el.is('input, textarea, select, button')
          $el.val value
        else
          $el.text value

    # Subviews
    # --------

    # Getting or adding a subview
    subview: (name, view) ->
      if name and view
        # Add the subview, ensure it’s unique
        @removeSubview name
        @subviews.push view
        @subviewsByName[name] = view
        view
      else if name
        # Get and return the subview by the given name
        @subviewsByName[name]

    # Removing a subview
    removeSubview: (nameOrView) ->
      return unless nameOrView

      if typeof nameOrView is 'string'
        # Name given, search for a subview by name
        name = nameOrView
        view = @subviewsByName[name]
      else
        # View instance given, search for the corresponding name
        view = nameOrView
        for otherName, otherView of @subviewsByName
          if view is otherView
            name = otherName
            break

      # Break if no view and name were found
      return unless name and view and view.dispose

      # Dispose the view
      view.dispose()

      # Remove the subview from the lists
      index = _(@subviews).indexOf(view)
      if index > -1
        @subviews.splice index, 1
      delete @subviewsByName[name]

    # Rendering
    # ---------

    # Get the model/collection data for the templating function
    # Uses optimized Chaplin serialization if available.
    getTemplateData: ->
      if @model
        templateData = if @model instanceof Model
          @model.serialize()
        else
          utils.beget @model.attributes
      else if @collection
        # Collection: Serialize all models
        if @collection instanceof Collection
          items = @collection.serialize()
        else
          items = []
          for model in @collection.models
            items.push utils.beget(model.attributes)
        templateData = {items}
      else
        # Empty object
        templateData = {}

      modelOrCollection = @model or @collection
      if modelOrCollection

        # If the model/collection is a Deferred, add a `resolved` flag,
        # but only if it’s not present yet
        if typeof modelOrCollection.state is 'function' and
          not ('resolved' of templateData)
            templateData.resolved = modelOrCollection.state() is 'resolved'

        # If the model/collection is a SyncMachine, add a `synced` flag,
        # but only if it’s not present yet
        if typeof modelOrCollection.isSynced is 'function' and
          not ('synced' of templateData)
            templateData.synced = modelOrCollection.isSynced()

      templateData

    # Returns the compiled template function
    getTemplateFunction: ->
      # Chaplin doesn’t define how you load and compile templates in order to
      # render views. The example application uses Handlebars and RequireJS
      # to load and compile templates on the client side. See the derived
      # View class in the example application:
      # https://github.com/chaplinjs/facebook-example/blob/master/coffee/views/base/view.coffee
      #
      # If you precompile templates to JavaScript functions on the server,
      # you might just return a reference to that function.
      # Several precompilers create a global `JST` hash which stores the
      # template functions. You can get the function by the template name:
      # JST[@templateName]

      throw new Error 'View#getTemplateFunction must be overridden'

    # Main render function
    # This method is bound to the instance in the constructor (see above)
    render: ->
      # Do not render if the object was disposed
      # (render might be called as an event handler which wasn’t
      # removed correctly)
      return false if @disposed

      templateFunc = @getTemplateFunction()
      if typeof templateFunc is 'function'

        # Call the template function passing the template data
        html = templateFunc @getTemplateData()

        # Replace HTML
        # ------------

        # This is a workaround for an apparent issue with jQuery 1.7’s
        # innerShiv feature. Using @$el.html(html) caused issues with
        # HTML5-only tags in IE7 and IE8.
        @$el.empty().append html

      # Call `afterRender` if `render` was not wrapped
      @afterRender() unless @renderIsWrapped

      # Return the view
      this

    # This method is called after a specific `render` of a derived class
    afterRender: ->
      # Automatically append to DOM if the container element is set
      if @container
        # Append the view to the DOM
        $(@container)[@containerMethod] @el
        # Trigger an event
        @trigger 'addedToDOM'

    # Disposal
    # --------

    disposed: false

    dispose: ->
      return if @disposed

      # Dispose subviews
      subview.dispose() for subview in @subviews

      # Unbind handlers of global events
      @unsubscribeAllEvents()

      # Unbind all model handlers
      @modelUnbindAll()

      # Remove all event handlers on this module
      @off()

      # Remove the topmost element from DOM. This also removes all event
      # handlers from the element and all its children.
      @$el.remove()

      # Remove element references, options,
      # model/collection references and subview lists
      properties = [
        'el', '$el',
        'options', 'model', 'collection',
        'subviews', 'subviewsByName',
        '_callbacks'
      ]
      delete this[prop] for prop in properties

      # Finished
      @disposed = true

      # You’re frozen when your heart’s not open
      Object.freeze? this

require.define 'chaplin/views/collection_view': (exports, require, module) ->
  $ = require 'jquery'
  _ = require 'underscore'
  View = require 'chaplin/views/view'

  # General class for rendering Collections.
  # Derive this class and declare at least `itemView` or override
  # `getView`. `getView` gets an item model and should instantiate
  # and return a corresponding item view.
  module.exports = class CollectionView extends View

    # Configuration options
    # ---------------------

    # These options may be overwritten in derived classes.

    # A class of item in collection.
    # This property has to be overridden by a derived class.
    itemView: null

    # Automatic rendering

    # Per default, render the view itself and all items on creation
    autoRender: true
    renderItems: true

    # Animation

    # When new items are added, their views are faded in.
    # Animation duration in milliseconds (set to 0 to disable fade in)
    animationDuration: 500

    # By default, fading in is done by javascript function which can be
    # slow on mobile devices. CSS animations are faster,
    # but require user’s manual definitions.
    # CSS classes used are: animated-item-view, animated-item-view-end.
    useCssAnimation: false

    # Selectors and Elements

    # A collection view may have a template and use one of its child elements
    # as the container of the item views. If you specify `listSelector`, the
    # item views will be appended to this element. If empty, $el is used.
    listSelector: null

    # The actual element which is fetched using `listSelector`
    $list: null

    # Selector for a fallback element which is shown if the collection is empty.
    fallbackSelector: null

    # The actual element which is fetched using `fallbackSelector`
    $fallback: null

    # Selector for a loading indicator element which is shown
    # while the collection is syncing.
    loadingSelector: null

    # The actual element which is fetched using `loadingSelector`
    $loading: null

    # Selector which identifies child elements belonging to collection
    # If empty, all children of $list are considered
    itemSelector: null

    # Filtering

    # The filter function, if any
    filterer: null

    # A function that will be executed after each filter.
    # Hides excluded items by default.
    filterCallback: (view, included) ->
      display = if included then '' else 'none'
      view.$el.stop(true, true).css('display', display)

    # View lists

    # Track a list of the visible views
    visibleItems: null

    # Initialization
    # --------------

    initialize: (options = {}) ->
      super

      # Initialize list for visible items
      @visibleItems = []

      # Start observing the collection
      @addCollectionListeners()

      # Apply options
      @renderItems = options.renderItems if options.renderItems?
      @itemView = options.itemView       if options.itemView?
      @filter options.filterer           if options.filterer?

    # Binding of collection listeners
    addCollectionListeners: ->
      @modelBind 'add',    @itemAdded
      @modelBind 'remove', @itemRemoved
      @modelBind 'reset',  @itemsResetted

    # Rendering
    # ---------

    # In contrast to normal views, a template is not mandatory
    # for CollectionViews. Provide an empty `getTemplateFunction`.
    getTemplateFunction: ->

    # Main render method (should be called only once)
    render: ->
      super

      # Set the $list property with the actual list container
      @$list = if @listSelector then @$(@listSelector) else @$el

      @initFallback()
      @initLoadingIndicator()

      # Render all items
      @renderAllItems() if @renderItems

    # Adding / Removing
    # -----------------

    # When an item is added, create a new view and insert it
    itemAdded: (item, collection, options = {}) =>
      @renderAndInsertItem item, options.index

    # When an item is removed, remove the corresponding view from DOM and caches
    itemRemoved: (item) =>
      @removeViewForItem item

    # When all items are resetted, render all anew
    itemsResetted: =>
      @renderAllItems()

    # Fallback message when the collection is empty
    # ---------------------------------------------

    initFallback: ->
      return unless @fallbackSelector

      # Set the $fallback property
      @$fallback = @$(@fallbackSelector)

      # Listen for visible items changes
      @on 'visibilityChange', @showHideFallback

      # Listen for sync events on the collection
      @modelBind 'syncStateChange', @showHideFallback

      # Set visibility initially
      @showHideFallback()

    # Show fallback if no item is visible and the collection is synced
    showHideFallback: =>
      visible = @visibleItems.length is 0 and (
        if typeof @collection.isSynced is 'function'
          # Collection is a SyncMachine
          @collection.isSynced()
        else
          # Assume it is synced
          true
      )
      @$fallback.css 'display', if visible then 'block' else 'none'

    # Loading indicator
    # -----------------

    initLoadingIndicator: ->
      # The loading indicator only works for Collections
      # which are SyncMachines.
      return unless @loadingSelector and
        typeof @collection.isSyncing is 'function'

      # Set the $loading property
      @$loading = @$(@loadingSelector)

      # Listen for sync events on the collection
      @modelBind 'syncStateChange', @showHideLoadingIndicator

      # Set visibility initially
      @showHideLoadingIndicator()

    showHideLoadingIndicator: ->
      # Only show the loading indicator if the collection is empty.
      # Otherwise loading more items in order to append them would
      # show the loading indicator. If you want the indicator to
      # show up in this case, you need to overwrite this method to
      # disable the check.
      visible = @collection.length is 0 and @collection.isSyncing()
      @$loading.css 'display', if visible then 'block' else 'none'

    # Filtering
    # ---------

    # Filters only child item views from all current subviews.
    getItemViews: ->
      itemViews = {}
      for name, view of @subviewsByName when name.slice(0, 9) is 'itemView:'
        itemViews[name.slice(9)] = view
      itemViews

    # Applies a filter to the collection view.
    # Expects an iterator function as first parameter
    # which need to return true or false.
    # Optional filter callback which is called to
    # show/hide the view or mark it otherwise as filtered.
    filter: (filterer, filterCallback) ->
      # Save the filterer and filterCallback functions
      @filterer = filterer
      @filterCallback = filterCallback if filterCallback
      filterCallback ?= @filterCallback

      # Show/hide existing views
      unless _(@getItemViews()).isEmpty()
        for item, index in @collection.models

          # Apply filter to the item
          included = if typeof filterer is 'function'
            filterer item, index
          else
            true

          # Show/hide the view accordingly
          view = @subview "itemView:#{item.cid}"
          # A view has not been created for this item yet
          unless view
            throw new Error 'CollectionView#filter: ' +
              "no view found for #{item.cid}"

          # Show/hide or mark the view accordingly
          @filterCallback view, included

          # Update visibleItems list, but do not trigger an event immediately
          @updateVisibleItems view.model, included, false

      # Trigger a combined `visibilityChange` event
      @trigger 'visibilityChange', @visibleItems

    # Item view rendering
    # -------------------

    # Render and insert all items
    renderAllItems: =>
      items = @collection.models

      # Reset visible items
      @visibleItems = []

      # Collect remaining views
      remainingViewsByCid = {}
      for item in items
        view = @subview "itemView:#{item.cid}"
        if view
          # View remains
          remainingViewsByCid[item.cid] = view

      # Remove old views of items not longer in the list
      for own cid, view of @getItemViews() when cid not of remainingViewsByCid
        # Remove the view
        @removeSubview "itemView:#{cid}"

      # Re-insert remaining items; render and insert new items
      for item, index in items
        # Check if view was already created
        view = @subview "itemView:#{item.cid}"
        if view
          # Re-insert the view
          @insertView item, view, index, false
        else
          # Create a new view, render and insert it
          @renderAndInsertItem item, index

      # If no view was created, trigger `visibilityChange` event manually
      unless items.length
        @trigger 'visibilityChange', @visibleItems

    # Render the view for an item
    renderAndInsertItem: (item, index) ->
      view = @renderItem item
      @insertView item, view, index

    # Instantiate and render an item using the `viewsByCid` hash as a cache
    renderItem: (item) ->
      # Get the existing view
      view = @subview "itemView:#{item.cid}"

      # Instantiate a new view if necessary
      unless view
        view = @getView item
        # Save the view in the subviews
        @subview "itemView:#{item.cid}", view

      # Render in any case
      view.render()

      view

    # Returns an instance of the view class. Override this
    # method to use several item view constructors depending
    # on the model type or data.
    getView: (model) ->
      if @itemView
        new @itemView {model}
      else
        throw new Error 'The CollectionView#itemView property ' +
          'must be defined or the getView() must be overridden.'

    # Inserts a view into the list at the proper position
    insertView: (item, view, index = null, enableAnimation = true) ->
      # Get the insertion offset
      position = if typeof index is 'number'
        index
      else
        @collection.indexOf item

      # Is the item included in the filter?
      included = if typeof @filterer is 'function'
        @filterer item, position
      else
        true

      # Get the view’s top element
      viewEl = view.el
      $viewEl = view.$el

      if included
        # Make view transparent if animation is enabled
        if enableAnimation
          if @useCssAnimation
            $viewEl.addClass 'animated-item-view'
          else
            $viewEl.css 'opacity', 0
      else
        # Hide the view if it’s filtered
        @filterCallback view, included

      # Insert the view into the list
      $list = @$list

      # Get the children which originate from item views
      children = if @itemSelector
        $list.children @itemSelector
      else
        $list.children()

      # Check if it needs to be inserted
      unless children.get(position) is viewEl
        length = children.length
        if length is 0 or position is length
          # Insert at the end
          $list.append viewEl
        else
          # Insert at the right position
          if position is 0
            $next = children.eq position
            $next.before viewEl
          else
            $previous = children.eq position - 1
            $previous.after viewEl

      # Tell the view that it was added to the DOM
      view.trigger 'addedToDOM'

      # Update the list of visible items, trigger a `visibilityChange` event
      @updateVisibleItems item, included

      # Fade the view in if it was made transparent before
      if enableAnimation and included
        if @useCssAnimation
          # Wait for DOM state change.
          setTimeout =>
            $viewEl.addClass 'animated-item-view-end'
          , 0
        else
          $viewEl.animate {opacity: 1}, @animationDuration

      return

    # Remove the view for an item
    removeViewForItem: (item) ->
      # Remove item from visibleItems list, trigger a `visibilityChange` event
      @updateVisibleItems item, false
      @removeSubview "itemView:#{item.cid}"

    # List of visible items
    # ---------------------

    # Update visibleItems list and trigger a `visibilityChanged` event
    # if an item changed its visibility
    updateVisibleItems: (item, includedInFilter, triggerEvent = true) ->
      visibilityChanged = false

      visibleItemsIndex = _(@visibleItems).indexOf item
      includedInVisibleItems = visibleItemsIndex > -1

      if includedInFilter and not includedInVisibleItems
        # Add item to the visible items list
        @visibleItems.push item
        visibilityChanged = true

      else if not includedInFilter and includedInVisibleItems
        # Remove item from the visible items list
        @visibleItems.splice visibleItemsIndex, 1
        visibilityChanged = true

      # Trigger a `visibilityChange` event if the visible items changed
      if visibilityChanged and triggerEvent
        @trigger 'visibilityChange', @visibleItems

      visibilityChanged

    # Disposal
    # --------

    dispose: ->
      return if @disposed

      # Remove jQuery objects, item view cache and visible items list
      properties = [
        '$list', '$fallback', '$loading',
        'visibleItems'
      ]
      delete this[prop] for prop in properties

      # Self-disposal
      super

require.define 'chaplin/lib/route': (exports, require, module) ->
  _ = require 'underscore'
  Backbone = require 'backbone'
  EventBroker = require 'chaplin/lib/event_broker'
  Controller = require 'chaplin/controllers/controller'

  module.exports = class Route

    # Borrow the static extend method from Backbone
    @extend = Backbone.Model.extend

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    reservedParams = ['path', 'changeURL']
    # Taken from Backbone.Router
    escapeRegExp = /[-[\]{}()+?.,\\^$|#\s]/g

    queryStringFieldSeparator = '&'
    queryStringValueSeparator = '='

    # Create a route for a URL pattern and a controller action
    # e.g. new Route '/users/:id', 'users#show'
    constructor: (pattern, target, @options = {}) ->
      # Save the raw pattern
      @pattern = pattern

      # Separate target into controller and controller action
      [@controller, @action] = target.split('#')

      # Check if the action is a reserved name
      if _(Controller.prototype).has @action
        throw new Error 'Route: You should not use existing controller properties as action names'

      @createRegExp()

    createRegExp: ->
      if _.isRegExp(@pattern)
        @regExp = @pattern
        return

      pattern = @pattern
        # Escape magic characters
        .replace(escapeRegExp, '\\$&')
        # Replace named parameters, collecting their names
        .replace(/(?::|\*)(\w+)/g, @addParamName)

      # Create the actual regular expression
      # Match until the end of the URL or the begin of query string
      @regExp = ///^#{pattern}(?=\?|$)///

    addParamName: (match, paramName) =>
      @paramNames ?= []
      # Test if parameter name is reserved
      if _(reservedParams).include(paramName)
        throw new Error "Route#addParamName: parameter name #{paramName} is reserved"
      # Save parameter name
      @paramNames.push paramName
      # Replace with a character class
      if match.charAt(0) is ':'
        # Regexp for :foo
        '([^\/\?]+)'
      else
        # Regexp for *foo
        '(.*?)'

    # Test if the route matches to a path (called by Backbone.History#loadUrl)
    test: (path) ->
      # Test the main RegExp
      matched = @regExp.test path
      return false unless matched

      # Apply the parameter constraints
      constraints = @options.constraints
      if constraints
        params = @extractParams path
        for own name, constraint of constraints
          unless constraint.test(params[name])
            return false

      return true

    # The handler which is called by Backbone.History when the route matched.
    # It is also called by Router#follow which might pass options
    handler: (path, options) =>
      # Build params hash
      params = @buildParams path, options

      # Publish a global matchRoute event passing the route and the params
      @publishEvent 'matchRoute', this, params

    # Create a proper Rails-like params hash, not an array like Backbone
    # `matches` and `additionalParams` arguments are optional
    buildParams: (path, options) ->
      params = {}

      # Add params from query string
      queryParams = @extractQueryParams path
      _(params).extend queryParams

      # Add named params from pattern matches
      patternParams = @extractParams path
      _(params).extend patternParams

      # Add additional params from options
      # (they might overwrite params extracted from URL)
      _(params).extend @options.params

      # Add a `changeURL` param whether to change the URL after routing
      # Defaults to false unless explicitly set in options
      params.changeURL = Boolean(options and options.changeURL)

      # Add a `path  param with the whole path match
      params.path = path

      params

    # Extract named parameters from the URL path
    extractParams: (path) ->
      params = {}

      # Apply the regular expression
      matches = @regExp.exec path

      # Fill the hash using the paramNames and the matches
      for match, index in matches.slice(1)
        paramName = if @paramNames then @paramNames[index] else index
        params[paramName] = match

      params

    # Extract parameters from the query string
    extractQueryParams: (path) ->
      params = {}

      regExp = /\?(.+?)(?=#|$)/
      matches = regExp.exec path
      return params unless matches

      queryString = matches[1]
      pairs = queryString.split queryStringFieldSeparator
      for pair in pairs
        continue unless pair.length
        [field, value] = pair.split queryStringValueSeparator
        continue unless field.length
        field = decodeURIComponent field
        value = decodeURIComponent value
        current = params[field]
        if current
          # Handle multiple params with same name:
          # Aggregate them in an array
          if current.push
            # Add the existing array
            current.push value
          else
            # Create a new array
            params[field] = [current, value]
        else
          params[field] = value

      params

require.define 'chaplin/lib/router': (exports, require, module) ->
  _ = require 'underscore'
  Backbone = require 'backbone'
  mediator = require 'chaplin/mediator'
  EventBroker = require 'chaplin/lib/event_broker'
  Route = require 'chaplin/lib/route'

  # The router which is a replacement for Backbone.Router.
  # Like the standard router, it creates a Backbone.History
  # instance and registers routes on it.

  module.exports = class Router # This class does not extend Backbone.Router

    # Borrow the static extend method from Backbone
    @extend = Backbone.Model.extend

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    constructor: (@options = {}) ->
      _(@options).defaults
        pushState: true

      @subscribeEvent '!router:route', @routeHandler
      @subscribeEvent '!router:changeURL', @changeURLHandler

      @createHistory()

    # Create a Backbone.History instance
    createHistory: ->
      Backbone.history or= new Backbone.History()

    startHistory: ->
      # Start the Backbone.History instance to start routing
      # This should be called after all routes have been registered
      Backbone.history.start @options

    # Stop the current Backbone.History instance from observing URL changes
    stopHistory: ->
      Backbone.history.stop() if Backbone.History.started

    # Connect an address with a controller action
    # Directly create a route on the Backbone.History instance
    match: (pattern, target, options = {}) =>
      # Create the route
      route = new Route pattern, target, options
      # Register the route at the Backbone.History instance.
      # Don’t use Backbone.history.route here because it calls
      # handlers.unshift, inserting the handler at the top of the list.
      # Since we want routes to match in the order they were specified,
      # we’re appending the route at the end.
      Backbone.history.handlers.push {route, callback: route.handler}
      route

    # Route a given URL path manually, returns whether a route matched
    # This looks quite like Backbone.History::loadUrl but it
    # accepts an absolute URL with a leading slash (e.g. /foo)
    # and passes a changeURL param to the callback function.
    route: (path) =>
      # Remove leading hash or slash
      path = path.replace /^(\/#|\/)/, ''
      for handler in Backbone.history.handlers
        if handler.route.test(path)
          handler.callback path, changeURL: true
          return true
      false

    # Handler for the global !router:route event
    routeHandler: (path, callback) ->
      routed = @route path
      callback? routed

    # Change the current URL, add a history entry.
    # Do not trigger any routes (which is Backbone’s
    # default behavior, but added for clarity)
    changeURL: (url) ->
      Backbone.history.navigate url, trigger: false

    # Handler for the global !router:changeURL event
    changeURLHandler: (url) ->
      @changeURL url

    # Disposal
    # --------

    disposed: false

    dispose: ->
      return if @disposed

      # Stop Backbone.History instance and remove it
      @stopHistory()
      delete Backbone.history

      @unsubscribeAllEvents()

      # Finished
      @disposed = true

      # You’re frozen when your heart’s not open
      Object.freeze? this

require.define 'chaplin/lib/event_broker': (exports, require, module) ->
  mediator = require 'chaplin/mediator'

  # Add functionality to subscribe and publish to global
  # Publish/Subscribe events so they can be removed afterwards
  # when disposing the object.
  #
  # Mixin this object to add the subscriber capability to any object:
  # _(object).extend EventBroker
  # Or to a prototype of a class:
  # _(@prototype).extend EventBroker
  #
  # Since Backbone 0.9.2 this abstraction just serves the purpose
  # that a handler cannot be registered twice for the same event.

  EventBroker =

    subscribeEvent: (type, handler) ->
      if typeof type isnt 'string'
        throw new TypeError 'EventBroker#subscribeEvent: ' +
          'type argument must be a string'
      if typeof handler isnt 'function'
        throw new TypeError 'EventBroker#subscribeEvent: ' +
          'handler argument must be a function'

      # Ensure that a handler isn’t registered twice
      mediator.unsubscribe type, handler, this

      # Register global handler, force context to the subscriber
      mediator.subscribe type, handler, this

    unsubscribeEvent: (type, handler) ->
      if typeof type isnt 'string'
        throw new TypeError 'EventBroker#unsubscribeEvent: ' +
          'type argument must be a string'
      if typeof handler isnt 'function'
        throw new TypeError 'EventBroker#unsubscribeEvent: ' +
          'handler argument must be a function'

      # Remove global handler
      mediator.unsubscribe type, handler

    # Unbind all global handlers
    unsubscribeAllEvents: ->
      # Remove all handlers with a context of this subscriber
      mediator.unsubscribe null, null, this

    publishEvent: (type, args...) ->
      if typeof type isnt 'string'
        throw new TypeError 'EventBroker#publishEvent: ' +
          'type argument must be a string'

      # Publish global handler
      mediator.publish type, args...

  # You’re frozen when your heart’s not open
  Object.freeze? EventBroker

  module.exports = EventBroker

require.define 'chaplin/lib/support': (exports, require, module) ->

  # Feature detection
  # -----------------

  support =

    # Test for defineProperty support
    # (IE 8 knows the method but will throw an exception)
    propertyDescriptors: do ->
      unless typeof Object.defineProperty is 'function' and
        typeof Object.defineProperties is 'function'
          return false
      try
        o = {}
        Object.defineProperty o, 'foo', value: 'bar'
        return o.foo is 'bar'
      catch error
        return false

  module.exports = support

require.define 'chaplin/lib/sync_machine': (exports, require, module) ->

  # Simple finite state machine for synchronization of models/collections
  # Three states: unsynced, syncing and synced
  # Several transitions between them
  # Fires Backbone events on every transition
  # (unsynced, syncing, synced; syncStateChange)
  # Provides shortcut methods to call handlers when a given state is reached
  # (named after the events above)

  UNSYNCED = 'unsynced'
  SYNCING  = 'syncing'
  SYNCED   = 'synced'

  STATE_CHANGE = 'syncStateChange'

  SyncMachine =

    _syncState: UNSYNCED
    _previousSyncState: null

    # Get the current state
    # ---------------------

    syncState: ->
      @_syncState

    isUnsynced: ->
      @_syncState is UNSYNCED

    isSynced: ->
      @_syncState is SYNCED

    isSyncing: ->
      @_syncState is SYNCING

    # Transitions
    # -----------

    unsync: ->
      if @_syncState in [SYNCING, SYNCED]
        @_previousSync = @_syncState
        @_syncState = UNSYNCED
        @trigger @_syncState, this, @_syncState
        @trigger STATE_CHANGE, this, @_syncState
      # when UNSYNCED do nothing
      return

    beginSync: ->
      if @_syncState in [UNSYNCED, SYNCED]
        @_previousSync = @_syncState
        @_syncState = SYNCING
        @trigger @_syncState, this, @_syncState
        @trigger STATE_CHANGE, this, @_syncState
      # when SYNCING do nothing
      return

    finishSync: ->
      if @_syncState is SYNCING
        @_previousSync = @_syncState
        @_syncState = SYNCED
        @trigger @_syncState, this, @_syncState
        @trigger STATE_CHANGE, this, @_syncState
      # when SYNCED, UNSYNCED do nothing
      return

    abortSync: ->
      if @_syncState is SYNCING
        @_syncState = @_previousSync
        @_previousSync = @_syncState
        @trigger @_syncState, this, @_syncState
        @trigger STATE_CHANGE, this, @_syncState
      # when UNSYNCED, SYNCED do nothing
      return

  # Create shortcut methods to bind a handler to a state change
  # -----------------------------------------------------------

  for event in [UNSYNCED, SYNCING, SYNCED, STATE_CHANGE]
    do (event) ->
      SyncMachine[event] = (callback, context = @) ->
        @on event, callback, context
        callback.call(context) if @_syncState is event

  # You’re frozen when your heart’s not open
  Object.freeze? SyncMachine

  module.exports = SyncMachine

require.define 'chaplin/lib/utils': (exports, require, module) ->
  support = require 'chaplin/lib/support'

  # Utilities
  # ---------

  utils =

    # Object Helpers
    # --------------

    # Prototypal delegation. Create an object which delegates
    # to another object.
    beget: do ->
      if typeof Object.create is 'function'
        Object.create
      else
        ctor = ->
        (obj) ->
          ctor:: = obj
          new ctor

    # Make properties readonly and not configurable
    # using ECMAScript 5 property descriptors
    readonly: do ->
      if support.propertyDescriptors
        readonlyDescriptor =
          writable: false
          enumerable: true
          configurable: false
        (obj, properties...) ->
          for prop in properties
            readonlyDescriptor.value = obj[prop]
            Object.defineProperty obj, prop, readonlyDescriptor
          true
      else
        ->
          false

    # String Helpers
    # --------------

    # Upcase the first character
    upcase: (str) ->
      str.charAt(0).toUpperCase() + str.substring(1)

    # underScoreHelper -> under_score_helper
    underscorize: (string) ->
      string.replace /[A-Z]/g, (char, index) ->
        (if index isnt 0 then '_' else '') + char.toLowerCase()

    # Event handling helpers
    # ----------------------

    # Returns whether a modifier key is pressed during a keypress or mouse click
    modifierKeyPressed: (event) ->
      event.shiftKey or event.altKey or event.ctrlKey or event.metaKey

  # Finish
  # ------

  # Seal the utils object
  Object.seal? utils

  module.exports = utils

require.define 'chaplin': (exports, require, module) ->
  Application = require 'chaplin/application'
  mediator = require 'chaplin/mediator'
  Dispatcher = require 'chaplin/dispatcher'
  Controller = require 'chaplin/controllers/controller'
  Collection = require 'chaplin/models/collection'
  Model = require 'chaplin/models/model'
  Layout = require 'chaplin/views/layout'
  View = require 'chaplin/views/view'
  CollectionView = require 'chaplin/views/collection_view'
  Route = require 'chaplin/lib/route'
  Router = require 'chaplin/lib/router'
  EventBroker = require 'chaplin/lib/event_broker'
  support = require 'chaplin/lib/support'
  SyncMachine = require 'chaplin/lib/sync_machine'
  utils = require 'chaplin/lib/utils'

  module.exports = {
    Application,
    mediator,
    Dispatcher,
    Controller,
    Collection,
    Model,
    Layout,
    View,
    CollectionView,
    Route,
    Router,
    EventBroker,
    support,
    SyncMachine,
    utils
  }