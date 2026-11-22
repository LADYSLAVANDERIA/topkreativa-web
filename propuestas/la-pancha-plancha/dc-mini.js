/* dc-mini.js — Top Kreativa
   Mini motor para páginas exportadas: {{huecos}}, bloques <template data-sc-for / data-sc-if>,
   eventos onX="{{fn}}" y una clase Component con state/setState como React. Sin dependencias. */
(function () {
  'use strict';
  var HOLE = /\{\{\s*([^}]+?)\s*\}\}/g;
  var WHOLE = /^\s*\{\{\s*([^}]+?)\s*\}\}\s*$/;

  function lookup(scope, path) {
    if (path === 'true') return true;
    if (path === 'false') return false;
    if (path === 'null') return null;
    if (/^-?\d+(\.\d+)?$/.test(path)) return Number(path);
    var parts = path.split('.'), v = scope;
    for (var i = 0; i < parts.length; i++) {
      if (v == null) return undefined;
      v = v[parts[i]];
    }
    return v;
  }
  function interp(str, scope) {
    return str.replace(HOLE, function (_, p) { var v = lookup(scope, p); return v == null ? '' : String(v); });
  }

  // ---- Instancia de un bloque: clona el fragmento y registra sus enlaces ----
  function Block(fragment, scope) {
    this.bindings = [];
    this.post = [];
    this.nodes = [];
    var frag = fragment.cloneNode(true);
    this.walk(frag);
    for (var c = frag.firstChild; c; c = c.nextSibling) this.nodes.push(c);
    this.frag = frag;
    this.update(scope);
  }
  Block.prototype.walk = function (node) {
    var self = this, child = node.firstChild;
    while (child) {
      var next = child.nextSibling;
      if (child.nodeType === 3) {
        if (child.nodeValue.indexOf('{{') >= 0) this.bindText(child);
      } else if (child.nodeType === 1) {
        if (child.tagName === 'TEMPLATE' && (child.hasAttribute('data-sc-for') || child.hasAttribute('data-sc-if'))) {
          this.bindControl(child);
        } else {
          this.bindAttrs(child);
          this.walk(child);
        }
      }
      child = next;
    }
  };
  Block.prototype.bindText = function (node) {
    var tpl = node.nodeValue;
    this.bindings.push(function (scope) {
      var v = interp(tpl, scope);
      if (node.nodeValue !== v) node.nodeValue = v;
    });
  };
  Block.prototype.bindAttrs = function (el) {
    var self = this, attrs = Array.prototype.slice.call(el.attributes);
    attrs.forEach(function (a) {
      var name = a.name, val = a.value;
      if (name.indexOf('hint-') === 0) { el.removeAttribute(name); return; }
      if (val.indexOf('{{') < 0) return;
      el.removeAttribute(name);
      var whole = WHOLE.exec(val);
      if (name.indexOf('on') === 0 && whole) {
        var evt = name.slice(2).toLowerCase(), path = whole[1];
        el.__h = el.__h || {};
        el.addEventListener(evt, function (e) { var f = el.__h[evt]; if (typeof f === 'function') f(e); });
        self.bindings.push(function (scope) { el.__h[evt] = lookup(scope, path); });
        return;
      }
      if (name === 'value' && (el.tagName === 'SELECT' || el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {
        self.post.push(function (scope) { var v = whole ? lookup(scope, whole[1]) : interp(val, scope); v = v == null ? '' : String(v); if (el.value !== v) el.value = v; });
        return;
      }
      self.bindings.push(function (scope) {
        var v;
        if (whole) {
          v = lookup(scope, whole[1]);
          if (v == null || v === false) { if (name.indexOf('aria-') === 0 && v === false) { el.setAttribute(name, 'false'); } else { el.removeAttribute(name); } return; }
          if (v === true) v = name.indexOf('aria-') === 0 ? 'true' : '';
          v = String(v);
        } else {
          v = interp(val, scope);
        }
        if (el.getAttribute(name) !== v) el.setAttribute(name, v);
      });
    });
  };
  Block.prototype.bindControl = function (tpl) {
    var anchor = document.createComment(tpl.hasAttribute('data-sc-for') ? 'for' : 'if');
    tpl.parentNode.replaceChild(anchor, tpl);
    var content = tpl.content;
    if (tpl.hasAttribute('data-sc-if')) {
      var cond = tpl.getAttribute('data-sc-if'), inst = null;
      this.bindings.push(function (scope) {
        var on = !!lookup(scope, cond);
        if (on && !inst) { inst = new Block(content, scope); anchor.parentNode.insertBefore(inst.frag, anchor.nextSibling); inst.mounted(); }
        else if (on && inst) { inst.update(scope); }
        else if (!on && inst) { inst.remove(); inst = null; }
      });
    } else {
      var listPath = tpl.getAttribute('data-sc-for'), as = tpl.getAttribute('data-as') || 'item', insts = [];
      this.bindings.push(function (scope) {
        var list = lookup(scope, listPath) || [];
        while (insts.length > list.length) insts.pop().remove();
        for (var i = 0; i < list.length; i++) {
          var s = Object.create(scope); s[as] = list[i]; s.$index = i;
          if (insts[i]) { insts[i].update(s); continue; }
          var b = new Block(content, s);
          var last = i === 0 ? anchor : insts[i - 1].nodes[insts[i - 1].nodes.length - 1];
          last.parentNode.insertBefore(b.frag, last.nextSibling);
          b.mounted();
          insts.push(b);
        }
      });
    }
  };
  Block.prototype.update = function (scope) {
    for (var i = 0; i < this.bindings.length; i++) this.bindings[i](scope);
    for (var j = 0; j < this.post.length; j++) this.post[j](scope);
  };
  Block.prototype.mounted = function () { this.frag = null; };
  Block.prototype.remove = function () {
    this.nodes.forEach(function (n) { if (n.parentNode) n.parentNode.removeChild(n); });
  };

  // ---- Clase base, al estilo de un componente de React ----
  function DCLogic(props) { this.props = props || {}; this.state = {}; this.__q = null; }
  DCLogic.prototype.setState = function (patch, cb) {
    var self = this;
    if (typeof patch === 'function') patch = patch(this.state, this.props);
    this.state = Object.assign({}, this.state, patch || {});
    if (cb) (this.__cbs = this.__cbs || []).push(cb);
    if (!this.__q) {
      this.__q = Promise.resolve().then(function () {
        self.__q = null; self.__render();
        var cbs = self.__cbs || []; self.__cbs = [];
        cbs.forEach(function (f) { try { f(); } catch (e) { console.error(e); } });
      });
    }
  };
  DCLogic.prototype.forceUpdate = function () { this.setState({}); };
  DCLogic.prototype.renderVals = function () { return {}; };

  function boot() {
    var tpl = document.getElementById('dc-template');
    var src = document.getElementById('dc-logic');
    var root = document.getElementById('dc-root');
    var Component = new Function('DCLogic', src.textContent + '\n;return Component;')(DCLogic);
    var comp = new Component({});
    var block = null;
    comp.__render = function () {
      var vals = comp.renderVals() || {};
      if (!block) { block = new Block(tpl.content, vals); root.appendChild(block.frag); block.mounted(); }
      else block.update(vals);
    };
    comp.__render();
    if (comp.componentDidMount) comp.componentDidMount();
    window.addEventListener('pagehide', function () { if (comp.componentWillUnmount) comp.componentWillUnmount(); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
