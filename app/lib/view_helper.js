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