# HAR Model Adapter Consumes Six Axis From Nine Axis Windows

Status: accepted

The mobile app continues to upload raw sensor windows in the existing 500x9 format, while the final HAR model adapter consumes the first six channels needed by the CNN and GRU model: accelerometer and gyroscope. This preserves the richer raw evidence contract and avoids changing the upload pipeline just because the current model does not use magnetometer channels.

**Considered Options**

- Change the mobile raw sensor contract to upload only 500x6 windows.
- Keep uploading 500x9 windows and let the backend HAR adapter project them to 500x6 for this model.

**Consequences**

The worker must validate that each raw window has 500 samples and at least six channels, then pass `samples[:, :, :6]` to the model. The model label `DRIVING` is mapped to the diary label `MOVING_VEHICLE` so persisted activity labels stay inside the existing domain vocabulary.
