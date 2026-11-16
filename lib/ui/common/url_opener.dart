import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser. Returns false if that failed.
typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> openInBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
