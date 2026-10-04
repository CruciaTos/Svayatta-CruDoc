# Imaging View Service

Cloud Run service for generating progressive JPEG 2000 viewing files and managing Firestore `radiology_views` documents.

## Deployment Commands (FOR USER — DO NOT RUN AUTOMATICALLY)

```bash
gcloud config set project svayatta-crudoc-dev
gcloud storage buckets list            # note the Firebase bucket name
gcloud run deploy imaging-view --source . --region asia-south1 \
  --no-allow-unauthenticated --memory 4Gi --cpu 2 --timeout 900 \
  --concurrency 1 --max-instances 5 --set-env-vars VIEW_CODEC=htj2k
gcloud eventarc triggers create imaging-view-finalized --location asia-south1 \
  --destination-run-service imaging-view --destination-run-region asia-south1 \
  --event-filters type=google.cloud.storage.object.v1.finalized \
  --event-filters bucket=<BUCKET> \
  --service-account <PROJECT_NUMBER>-compute@developer.gserviceaccount.com
gcloud eventarc triggers create imaging-view-deleted --location asia-south1 \
  --destination-run-service imaging-view --destination-run-region asia-south1 \
  --event-filters type=google.cloud.storage.object.v1.deleted \
  --event-filters bucket=<BUCKET> \
  --service-account <PROJECT_NUMBER>-compute@developer.gserviceaccount.com
```

- The trigger `--location` must equal the bucket's location. Check it with `gcloud storage buckets describe gs://<BUCKET> --format="value(location)"`; if it isn't `ASIA-SOUTH1`, stop and ask Claude (data residency).
- The trigger's service account needs `roles/eventarc.eventReceiver` and `roles/run.invoker`; the Cloud Run service account needs `roles/datastore.user` and `roles/storage.objectAdmin`.
- The Cloud Storage service agent needs `roles/pubsub.publisher` for Eventarc storage triggers.