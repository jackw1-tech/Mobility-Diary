# HAR Inference Runs Inside Celery Worker

Status: accepted

HAR inference should run inside the Celery worker rather than in the Django request path or a separate inference service. The web API remains responsible for upload coordination and status transitions; the worker owns TensorFlow/Keras dependencies, lazy model loading, cached model instances, and final diary enrichment.

**Considered Options**

- Load and run TensorFlow from Django API requests.
- Deploy a separate model inference service.
- Run TensorFlow inside the existing Celery worker.

**Consequences**

The immediate deployment stays simpler for the project while keeping expensive inference outside HTTP requests. The worker image or runtime must include TensorFlow and the `.keras` artifacts, and future scaling can separate worker concurrency from web concurrency without changing the public API.
