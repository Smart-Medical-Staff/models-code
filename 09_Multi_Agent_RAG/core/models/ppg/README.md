Place optional PPG inference artifacts here:

- `scaler.pkl`
- one of `rf_model.pkl`, `gb_model.pkl`, `svm_model.pkl`, `ppg_model.pkl`
- or `ppg_to_risk_model.tflite`

These files are loaded only for inference. Training, evaluation, plotting, and
synthetic dataset generation remain outside the production workflow.
