# CruDoc Cloud Functions

## Deploying

Deploy only with the Firebase CLI, from the `CruDoc/` folder:

```
firebase deploy --only functions:<functionName> --project svayatta-crudoc-dev
```

On Windows set `FUNCTIONS_DISCOVERY_TIMEOUT=90` first, or the CLI times out while loading the code.

Do not use **Redeploy** or **Edit & deploy new revision** in the Cloud Run console for these services.
The console reuses the old build image, which Artifact Registry may already have deleted, and the update
fails with "Routing traffic: Failed … Image '…gcf-artifacts/…' not found". If that happens, run the
`firebase deploy` above for that function. It builds a fresh image.

## Endpoints that must be reachable without Google sign-in

The project's organisation blocks `allUsers`, so after a function's **first** deploy Google rejects
outside calls with its own "403 Forbidden" page. Turn Google's check off once per service (the
function still checks its own login or API key):

```
gcloud run services update <servicename> --no-invoker-iam-check --region asia-south1 --project svayatta-crudoc-dev
```

`<servicename>` is the function name in lower case, e.g. `getavailability`. Later `firebase deploy`
runs keep this setting.
