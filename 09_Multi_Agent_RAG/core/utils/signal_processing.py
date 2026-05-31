from __future__ import annotations

from typing import Dict, Iterable, Tuple

import numpy as np

SAMPLING_RATE = 100
FEATURE_NAMES = [
    "HR",
    "Mean_IBI",
    "SDNN",
    "RMSSD",
    "CV_IBI",
    "Amp_Mean_Red",
    "Amp_Mean_IR",
    "Amp_Std_Red",
    "Amp_Std_IR",
    "Rise_Time_Red",
    "Rise_Time_IR",
    "Red_IR_Ratio_Mean",
    "Red_IR_Peak_Ratio",
    "Sig_Power_Red",
    "Sig_Power_IR",
    "SNR_Red",
    "SNR_IR",
    "Regularity",
]


def as_float_array(values: Iterable[float]) -> np.ndarray:
    arr = np.asarray(list(values), dtype=np.float64)
    return arr[np.isfinite(arr)]


def dc_removal(signal: np.ndarray) -> np.ndarray:
    return signal - np.mean(signal)


def _moving_average(signal: np.ndarray, window: int) -> np.ndarray:
    window = max(3, int(window))
    if window % 2 == 0:
        window += 1
    if len(signal) < window:
        return signal
    kernel = np.ones(window, dtype=np.float64) / window
    return np.convolve(signal, kernel, mode="same")


def bandpass_filter(
    signal: np.ndarray,
    fs: int = SAMPLING_RATE,
    lowcut: float = 0.5,
    highcut: float = 5.0,
) -> np.ndarray:
    """
    Notebook-equivalent PPG conditioning without a hard SciPy dependency.

    Prefer scipy's zero-phase Butterworth filter when available. Fall back to a
    deterministic high-pass/low-pass moving-average approximation so the system
    remains importable in lean deployments and tests.
    """
    try:
        from scipy.signal import butter, filtfilt  # type: ignore

        nyq = 0.5 * fs
        b, a = butter(4, [lowcut / nyq, highcut / nyq], btype="band")
        return filtfilt(b, a, signal)
    except Exception:
        low_window = max(3, int(fs / max(highcut, 0.1)))
        high_window = max(low_window + 2, int(fs / max(lowcut, 0.1)))
        low_passed = _moving_average(signal, low_window)
        baseline = _moving_average(signal, high_window)
        return low_passed - baseline


def minmax_normalize(signal: np.ndarray) -> np.ndarray:
    span = np.max(signal) - np.min(signal)
    return (signal - np.min(signal)) / (span + 1e-8)


def preprocess_signal(
    raw_red: Iterable[float],
    raw_ir: Iterable[float],
    fs: int = SAMPLING_RATE,
) -> Tuple[np.ndarray, np.ndarray]:
    red = as_float_array(raw_red)
    ir = as_float_array(raw_ir)
    min_len = min(len(red), len(ir))
    if min_len == 0:
        raise ValueError("PPG red/IR channels contain no finite samples")
    red = red[:min_len]
    ir = ir[:min_len]
    red_clean = minmax_normalize(bandpass_filter(dc_removal(red), fs=fs))
    ir_clean = minmax_normalize(bandpass_filter(dc_removal(ir), fs=fs))
    return red_clean, ir_clean


def find_ppg_peaks(signal: np.ndarray, fs: int = SAMPLING_RATE) -> np.ndarray:
    distance = max(1, int(fs * 0.4))
    try:
        from scipy.signal import find_peaks  # type: ignore

        peaks, _ = find_peaks(signal, distance=distance)
    except Exception:
        candidates = []
        last_peak = -distance
        for idx in range(1, len(signal) - 1):
            if signal[idx] > signal[idx - 1] and signal[idx] >= signal[idx + 1]:
                if idx - last_peak >= distance:
                    candidates.append(idx)
                    last_peak = idx
                elif candidates and signal[idx] > signal[candidates[-1]]:
                    candidates[-1] = idx
                    last_peak = idx
        peaks = np.asarray(candidates, dtype=int)

    if len(peaks) == 0:
        return peaks
    peak_heights = signal[peaks]
    threshold = float(np.median(peak_heights) * 0.5)
    return peaks[peak_heights > threshold]


def signal_snr(signal: np.ndarray) -> float:
    noise = signal - _moving_average(signal, 20)
    signal_var = float(np.var(signal))
    if signal_var <= 1e-12:
        return -120.0
    return float(10 * np.log10(signal_var / (float(np.var(noise)) + 1e-10)))


def extract_features(
    signal_red: np.ndarray,
    signal_ir: np.ndarray,
    fs: int = SAMPLING_RATE,
) -> Dict[str, float]:
    peaks = find_ppg_peaks(signal_red, fs=fs)
    if len(peaks) < 4:
        raise ValueError("Too few PPG peaks for reliable feature extraction")

    ibi = np.diff(peaks) / fs
    hr = 60.0 / np.mean(ibi)
    mean_ibi = np.mean(ibi)
    sdnn = np.std(ibi)
    rmssd = np.sqrt(np.mean(np.square(np.diff(ibi)))) if len(ibi) > 1 else np.nan
    cv_ibi = sdnn / mean_ibi if mean_ibi > 0 else np.nan

    amp_red = signal_red[peaks]
    amp_ir = signal_ir[peaks]
    amp_mean_red = np.mean(amp_red)
    amp_mean_ir = np.mean(amp_ir)
    amp_std_red = np.std(amp_red)
    amp_std_ir = np.std(amp_ir)

    rise_times_red = []
    rise_times_ir = []
    for peak in peaks:
        if peak < fs * 0.1 or peak + fs * 0.2 >= len(signal_red):
            continue
        red_window = signal_red[max(0, peak - int(fs * 0.3)) : peak]
        ir_window = signal_ir[max(0, peak - int(fs * 0.3)) : peak]
        if len(red_window):
            red_trough = peak - int(np.argmin(red_window))
            rise_times_red.append(float((peak - red_trough) / fs))
        if len(ir_window):
            ir_trough = peak - int(np.argmin(ir_window))
            rise_times_ir.append(float((peak - ir_trough) / fs))

    regularity_corrs = []
    for idx in range(len(peaks) - 2):
        seg1 = signal_red[peaks[idx] : peaks[idx + 1]]
        seg2 = signal_red[peaks[idx + 1] : peaks[idx + 2]]
        if len(seg1) < 4 or len(seg2) < 4:
            continue
        seg1_r = np.interp(np.linspace(0, 1, 50), np.linspace(0, 1, len(seg1)), seg1)
        seg2_r = np.interp(np.linspace(0, 1, 50), np.linspace(0, 1, len(seg2)), seg2)
        corr = float(np.corrcoef(seg1_r, seg2_r)[0, 1])
        regularity_corrs.append(corr if np.isfinite(corr) else 0.0)

    values = [
        hr,
        mean_ibi,
        sdnn,
        rmssd,
        cv_ibi,
        amp_mean_red,
        amp_mean_ir,
        amp_std_red,
        amp_std_ir,
        np.mean(rise_times_red) if rise_times_red else np.nan,
        np.mean(rise_times_ir) if rise_times_ir else np.nan,
        np.mean(signal_red) / (np.mean(signal_ir) + 1e-8),
        amp_mean_red / (amp_mean_ir + 1e-8),
        np.var(signal_red),
        np.var(signal_ir),
        signal_snr(signal_red),
        signal_snr(signal_ir),
        np.mean(regularity_corrs) if regularity_corrs else 0.0,
    ]
    if not np.all(np.isfinite(values)):
        raise ValueError("Feature extraction produced non-finite values")
    return dict(zip(FEATURE_NAMES, [float(v) for v in values]))


def feature_vector(features: Dict[str, float]) -> np.ndarray:
    return np.asarray([[features[name] for name in FEATURE_NAMES]], dtype=np.float32)
