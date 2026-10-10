// Raw mouse input for Godot's pointer lock in the browser.
// Measured on a Windows PC in Chrome: standard pointer lock mixes cursor
// recentring artefacts into movementX (676-923 px jumps next to a [0,0]
// packet) and makes the camera uncontrollable; raw input has none.
(() => {
  'use strict';
  const proto = Element.prototype;
  const original = proto.requestPointerLock;
  if (!original) return;
  window.__rawPointer = false;
  proto.requestPointerLock = function (options) {
    const element = this;
    let result;
    try {
      result = original.call(element, Object.assign({}, options, { unadjustedMovement: true }));
    } catch (error) {
      window.__rawPointer = false;
      return original.call(element, options);
    }
    if (result && typeof result.then === 'function') {
      return result.then(
        () => { window.__rawPointer = true; },
        () => { window.__rawPointer = false; return original.call(element, options); }
      );
    }
    window.__rawPointer = true;
    return result;
  };
  // Fallback when raw input is refused: drop packets within 2 ms after a
  // recentring marker before Godot sees them.
  let lastZero = -1e9;
  const filter = (event) => {
    if (window.__rawPointer || !document.pointerLockElement) return;
    if (event.movementX === 0 && event.movementY === 0) {
      lastZero = event.timeStamp;
      return;
    }
    if (event.timeStamp - lastZero < 2) event.stopImmediatePropagation();
  };
  window.addEventListener('pointermove', filter, true);
  window.addEventListener('mousemove', filter, true);
})();
