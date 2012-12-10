(function(/*! Brunch !*/) {
  'use strict';

  var globals = typeof window !== 'undefined' ? window : global;
  if (typeof globals.require === 'function') return;

  var modules = {};
  var cache = {};

  var has = function(object, name) {
    return ({}).hasOwnProperty.call(object, name);
  };

  var expand = function(root, name) {
    var results = [], parts, part;
    if (/^\.\.?(\/|$)/.test(name)) {
      parts = [root, name].join('/').split('/');
    } else {
      parts = name.split('/');
    }
    for (var i = 0, length = parts.length; i < length; i++) {
      part = parts[i];
      if (part === '..') {
        results.pop();
      } else if (part !== '.' && part !== '') {
        results.push(part);
      }
    }
    return results.join('/');
  };

  var dirname = function(path) {
    return path.split('/').slice(0, -1).join('/');
  };

  var localRequire = function(path) {
    return function(name) {
      var dir = dirname(path);
      var absolute = expand(dir, name);
      return globals.require(absolute);
    };
  };

  var initModule = function(name, definition) {
    var module = {id: name, exports: {}};
    definition(module.exports, localRequire(name), module);
    var exports = cache[name] = module.exports;
    return exports;
  };

  var require = function(name) {
    var path = expand(name, '.');

    if (has(cache, path)) return cache[path];
    if (has(modules, path)) return initModule(path, modules[path]);

    var dirIndex = expand(path, './index');
    if (has(cache, dirIndex)) return cache[dirIndex];
    if (has(modules, dirIndex)) return initModule(dirIndex, modules[dirIndex]);

    throw new Error('Cannot find module "' + name + '"');
  };

  var define = function(bundle) {
    for (var key in bundle) {
      if (has(bundle, key)) {
        modules[key] = bundle[key];
      }
    }
  }

  globals.require = require;
  globals.require.define = define;
  globals.require.brunch = true;
})();

window.require.define({"application": function(exports, require, module) {
  // Application bootstrapper.
  Application = {
    initialize: function() {
      var HomeView = require('views/home_view');
      var Router = require('lib/router');
      // Ideally, initialized classes should be kept in controllers & mediator.
      // If you're making big webapp, here's more sophisticated skeleton
      // https://github.com/paulmillr/brunch-with-chaplin
      this.homeView = new HomeView();
      this.router = new Router();
      if (typeof Object.freeze === 'function') Object.freeze(this);
    }
  }

  module.exports = Application;
  
}});

window.require.define({"initialize": function(exports, require, module) {
  var application = require('application');

  $(function() {
    application.initialize();
    Backbone.history.start();
  });
  
}});

window.require.define({"lib/router": function(exports, require, module) {
  var application = require('application');

  module.exports = Backbone.Router.extend({
    routes: {
      '': 'home'
    },

    home: function() {
      $('body').html(application.homeView.render().el);
    }
  });
  
}});

window.require.define({"lib/view_helper": function(exports, require, module) {
  // Put your handlebars.js helpers here.
  Handlebars.loadPartial = function (name) {
    var partial = handlebars.partials[name];
    if (typeof partial === "string") {
      partial = handlebars.compile(partial);
      handlebars.partials[name] = partial;
    }
    return partial;
  };

  Handlebars.registerHelper("block",
    function (name, options) {
      /* Look for partial by name. */
      var partial = Handlebars.loadPartial(name) || options.fn;
      return partial(this, { data : options.hash });
  });

  Handlebars.registerHelper("partial",
    function (name, options) {
      Handlebars.registerPartial(name, options.fn);
  });
}});

window.require.define({"models/collection": function(exports, require, module) {
  // Base class for all collections.
  module.exports = Backbone.Collection.extend({
    
  });
  
}});

window.require.define({"models/model": function(exports, require, module) {
  // Base class for all models.
  module.exports = Backbone.Model.extend({
    
  });
  
}});

window.require.define({"views/home_view": function(exports, require, module) {
  var View = require('./view');
  var template = require('./templates/home');

  module.exports = View.extend({
    id: 'home-view',
    template: template
  });
  
}});

window.require.define({"views/templates/base": function(exports, require, module) {
  module.exports = Handlebars.template(function (Handlebars,depth0,helpers,partials,data) {
    helpers = helpers || Handlebars.helpers; partials = partials || Handlebars.partials;
    var buffer = "", stack1, stack2, foundHelper, tmp1, self=this, functionType="function", blockHelperMissing=helpers.blockHelperMissing, helperMissing=helpers.helperMissing, undef=void 0, escapeExpression=this.escapeExpression;

  function program1(depth0,data) {
    
    
    return " Default Title ";}

  function program3(depth0,data) {
    
    
    return "\n    This will be default content that appears in a\n    deriving template if it does not declare a\n    replacement for the \"content\" section.\n  ";}

  function program5(depth0,data) {
    
    
    return " Home ";}

  function program7(depth0,data) {
    
    
    return " HOME ";}

  function program9(depth0,data) {
    
    
    return " About ";}

  function program11(depth0,data) {
    
    
    return " ABOUT ";}

    buffer += "<html>\n<head>\n  <title>";
    foundHelper = helpers.title;
    stack1 = foundHelper || depth0.title;
    tmp1 = self.program(1, program1, data);
    tmp1.hash = {};
    tmp1.fn = tmp1;
    tmp1.inverse = self.noop;
    if(foundHelper && typeof stack1 === functionType) { stack1 = stack1.call(depth0, tmp1); }
    else { stack1 = blockHelperMissing.call(depth0, stack1, tmp1); }
    if(stack1 || stack1 === 0) { buffer += stack1; }
    buffer += "</title>\n</head>\n<body>\n  ";
    stack1 = depth0;
    stack1 = self.invokePartial(partials.header, 'header', stack1, helpers, partials);;
    if(stack1 || stack1 === 0) { buffer += stack1; }
    buffer += "\n  ";
    foundHelper = helpers.content;
    stack1 = foundHelper || depth0.content;
    tmp1 = self.program(3, program3, data);
    tmp1.hash = {};
    tmp1.fn = tmp1;
    tmp1.inverse = self.noop;
    if(foundHelper && typeof stack1 === functionType) { stack1 = stack1.call(depth0, tmp1); }
    else { stack1 = blockHelperMissing.call(depth0, stack1, tmp1); }
    if(stack1 || stack1 === 0) { buffer += stack1; }
    buffer += "\n  ";
    stack1 = depth0;
    stack1 = self.invokePartial(partials.footer, 'footer', stack1, helpers, partials);;
    if(stack1 || stack1 === 0) { buffer += stack1; }
    buffer += "\n</body>\n</html>\n\n<!-- home.hbs -->\n";
    foundHelper = helpers.base;
    stack1 = foundHelper || depth0.base;
    foundHelper = helpers.derives;
    stack2 = foundHelper || depth0.derives;
    if(typeof stack2 === functionType) { stack1 = stack2.call(depth0, stack1, { hash: {} }); }
    else if(stack2=== undef) { stack1 = helperMissing.call(depth0, "derives", stack1, { hash: {} }); }
    else { stack1 = stack2; }
    buffer += escapeExpression(stack1) + "\n";
    foundHelper = helpers.title;
    stack1 = foundHelper || depth0.title;
    tmp1 = self.program(5, program5, data);
    tmp1.hash = {};
    tmp1.fn = tmp1;
    tmp1.inverse = self.noop;
    if(foundHelper && typeof stack1 === functionType) { stack1 = stack1.call(depth0, tmp1); }
    else { stack1 = blockHelperMissing.call(depth0, stack1, tmp1); }
    if(stack1 || stack1 === 0) { buffer += stack1; }
    buffer += "\n";
    foundHelper = helpers.content;
    stack1 = foundHelper || depth0.content;
    tmp1 = self.program(7, program7, data);
    tmp1.hash = {};
    tmp1.fn = tmp1;
    tmp1.inverse = self.noop;
    if(foundHelper && typeof stack1 === functionType) { stack1 = stack1.call(depth0, tmp1); }
    else { stack1 = blockHelperMissing.call(depth0, stack1, tmp1); }
    if(stack1 || stack1 === 0) { buffer += stack1; }
    buffer += "\n\n<!-- about.hbs -->\n";
    foundHelper = helpers.base;
    stack1 = foundHelper || depth0.base;
    foundHelper = helpers.derives;
    stack2 = foundHelper || depth0.derives;
    if(typeof stack2 === functionType) { stack1 = stack2.call(depth0, stack1, { hash: {} }); }
    else if(stack2=== undef) { stack1 = helperMissing.call(depth0, "derives", stack1, { hash: {} }); }
    else { stack1 = stack2; }
    buffer += escapeExpression(stack1) + "\n";
    foundHelper = helpers.title;
    stack1 = foundHelper || depth0.title;
    tmp1 = self.program(9, program9, data);
    tmp1.hash = {};
    tmp1.fn = tmp1;
    tmp1.inverse = self.noop;
    if(foundHelper && typeof stack1 === functionType) { stack1 = stack1.call(depth0, tmp1); }
    else { stack1 = blockHelperMissing.call(depth0, stack1, tmp1); }
    if(stack1 || stack1 === 0) { buffer += stack1; }
    buffer += "\n";
    foundHelper = helpers.content;
    stack1 = foundHelper || depth0.content;
    tmp1 = self.program(11, program11, data);
    tmp1.hash = {};
    tmp1.fn = tmp1;
    tmp1.inverse = self.noop;
    if(foundHelper && typeof stack1 === functionType) { stack1 = stack1.call(depth0, tmp1); }
    else { stack1 = blockHelperMissing.call(depth0, stack1, tmp1); }
    if(stack1 || stack1 === 0) { buffer += stack1; }
    return buffer;});
}});

window.require.define({"views/templates/home": function(exports, require, module) {
  module.exports = Handlebars.template(function (Handlebars,depth0,helpers,partials,data) {
    helpers = helpers || Handlebars.helpers; partials = partials || Handlebars.partials;
    var buffer = "", stack1, stack2, foundHelper, tmp1, self=this, functionType="function", blockHelperMissing=helpers.blockHelperMissing;

  function program1(depth0,data) {
    
    
    return " Home ";}

  function program3(depth0,data) {
    
    
    return " HOME ";}

    stack1 = "title";
    foundHelper = helpers.partial;
    stack2 = foundHelper || depth0.partial;
    tmp1 = self.program(1, program1, data);
    tmp1.hash = {};
    tmp1.fn = tmp1;
    tmp1.inverse = self.noop;
    if(foundHelper && typeof stack2 === functionType) { stack1 = stack2.call(depth0, stack1, tmp1); }
    else { stack1 = blockHelperMissing.call(depth0, stack2, stack1, tmp1); }
    if(stack1 || stack1 === 0) { buffer += stack1; }
    buffer += "\n";
    stack1 = "content";
    foundHelper = helpers.partial;
    stack2 = foundHelper || depth0.partial;
    tmp1 = self.program(3, program3, data);
    tmp1.hash = {};
    tmp1.fn = tmp1;
    tmp1.inverse = self.noop;
    if(foundHelper && typeof stack2 === functionType) { stack1 = stack2.call(depth0, stack1, tmp1); }
    else { stack1 = blockHelperMissing.call(depth0, stack2, stack1, tmp1); }
    if(stack1 || stack1 === 0) { buffer += stack1; }
    buffer += "\n";
    stack1 = depth0;
    stack1 = self.invokePartial(partials.base, 'base', stack1, helpers, partials);;
    if(stack1 || stack1 === 0) { buffer += stack1; }
    return buffer;});
}});

window.require.define({"views/view": function(exports, require, module) {
  require('lib/view_helper');

  // Base class for all views.
  module.exports = Backbone.View.extend({
    initialize: function() {
      this.render = _.bind(this.render, this);
    },

    template: function() {},
    getRenderData: function() {},

    render: function() {
      this.$el.html(this.template(this.getRenderData()));
      this.afterRender();
      return this;
    },

    afterRender: function() {}
  });
  
}});

