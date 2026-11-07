// Viewer-request rewrite for the S3 origin, which has no directory indexes:
//   /projects/focus-bank/  -> /projects/focus-bank/index.html
//   /projects/focus-bank   -> /projects/focus-bank/index.html
// Paths whose last segment has an extension (/assets/css/site.css) pass through unchanged.
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (uri.endsWith('/')) {
    request.uri = uri + 'index.html';
  } else if (uri.substring(uri.lastIndexOf('/') + 1).indexOf('.') === -1) {
    request.uri = uri + '/index.html';
  }
  return request;
}
