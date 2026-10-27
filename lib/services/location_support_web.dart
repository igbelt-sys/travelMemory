import 'dart:js_interop';

@JS('globalThis.isSecureContext')
external bool get _secureContext;

@JS('globalThis.navigator.geolocation')
external JSObject? get _geolocation;

bool browserLocationSupported() => _secureContext && _geolocation != null;
