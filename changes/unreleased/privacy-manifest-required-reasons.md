The privacy manifests declare the required-reason APIs the bundles use:
UserDefaults (CA92.1) for the app and file metadata (C617.1, plus 3B52.1 for the
chosen export folder) for the app, widget and Mac companion. policycheck fails
when a bundle uses one it does not declare (#34).
