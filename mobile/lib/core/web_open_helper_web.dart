import 'dart:html' as html;

html.WindowBase? openBlankWindow() => html.window.open('', '_blank');

void redirectWindow(dynamic handle, String url) {
  (handle as html.WindowBase?)?.location.href = url;
}
