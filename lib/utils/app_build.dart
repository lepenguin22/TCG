/// Which build of the app this is.
///
/// The release workflow passes the tag in, so an installed copy can say which
/// release it came from. A build made by hand has nothing to pass and says so.
///
/// It doubles as the fingerprint of everything bundled with the app, the card
/// database included: a new database can only reach a phone inside a new
/// build, so a build that is not the one last seen is the one thing that says
/// "what shipped with this copy may have changed".
const appBuildVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'Local build',
);
