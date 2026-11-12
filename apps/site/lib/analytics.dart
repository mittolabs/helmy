/// helmy.ke's id in our Umami (stats.ashlar.ke, run on the server helmy.ke shares
/// with the Ashlar sites). Chosen here and registered there by ashlar-icons-site's
/// deploy (umami_websites in its inventory), so the two always agree.
const umamiWebsiteId = '18b74646-66fa-4633-b9a1-6d2e8cc5db41';

/// The tracker's tags, for the site's head and, through tool/web.dart, the docs'.
/// First-party under /u/ (the edge passes it to Umami), no cookie, nothing counted
/// when Do Not Track is on, and only on helmy.ke itself.
const trackerTags =
    '<script defer src="/u/script.js" data-website-id="$umamiWebsiteId" '
    'data-domains="helmy.ke" data-do-not-track="true"></script>'
    '<script defer src="/track.js"></script>';

/// An event Umami counts when the element is clicked: [name], with [data] as its
/// properties ("download", {"file": "macos-arm64"}).
Map<String, String> track(String name, [Map<String, String> data = const {}]) => {
  'data-umami-event': name,
  for (final MapEntry(:key, :value) in data.entries) 'data-umami-event-$key': value,
};
