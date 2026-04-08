import Foundation
import Accelerate

/// Extracts frequency-domain features from motion sample buffers using FFT (vDSP).
/// Used by the continuous gesture recognition layer.
nonisolated struct FrequencyAnalyzer: Sendable {

    /// Extract the dominant frequency from acceleration magnitude signal.
    /// - Parameters:
    ///   - samples: Motion samples at ~100Hz
    ///   - sampleRate: Samples per second (default 100Hz)
    /// - Returns: Dominant frequency in Hz
    static func dominantFrequency(from samples: [MotionSample], sampleRate: Double = 100.0) -> Double {
        let magnitudes = samples.map { $0.userAcceleration.magnitude }
        return dominantFrequencyFromSignal(magnitudes, sampleRate: sampleRate)
    }

    /// Zero-crossing rate of the acceleration magnitude signal.
    static func zeroCrossingRate(from samples: [MotionSample], sampleRate: Double = 100.0) -> Double {
        let magnitudes = samples.map { $0.userAcceleration.magnitude }
        guard magnitudes.count >= 2 else { return 0 }

        let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
        let centered = magnitudes.map { $0 - mean }

        var crossings = 0
        for i in 1..<centered.count {
            if (centered[i - 1] >= 0 && centered[i] < 0) || (centered[i - 1] < 0 && centered[i] >= 0) {
                crossings += 1
            }
        }

        let duration = Double(magnitudes.count) / sampleRate
        return Double(crossings) / (2.0 * duration) // divide by 2 to convert crossings to cycles
    }

    /// Energy distribution across frequency bands.
    static func frequencyBandEnergies(from samples: [MotionSample], bands: Int = 8, sampleRate: Double = 100.0) -> [Double] {
        let magnitudes = samples.map { $0.userAcceleration.magnitude }
        let spectrum = fftMagnitudeSpectrum(magnitudes)
        guard !spectrum.isEmpty else { return [Double](repeating: 0, count: bands) }

        let binSize = max(1, spectrum.count / bands)
        var energies = [Double](repeating: 0, count: bands)

        for band in 0..<bands {
            let start = band * binSize
            let end = min(start + binSize, spectrum.count)
            guard start < end else { continue }
            energies[band] = spectrum[start..<end].reduce(0) { $0 + $1 * $1 }
        }

        // Normalize
        let total = energies.reduce(0, +)
        if total > 1e-10 {
            energies = energies.map { $0 / total }
        }

        return energies
    }

    /// Normalized energy per axis (x, y, z of userAcceleration).
    /// Distinguishes shake (single axis dominant) from circle (multiple axes).
    static func axisEnergyDistribution(from samples: [MotionSample]) -> Vector3 {
        var ex = 0.0, ey = 0.0, ez = 0.0
        for s in samples {
            ex += s.userAcceleration.x * s.userAcceleration.x
            ey += s.userAcceleration.y * s.userAcceleration.y
            ez += s.userAcceleration.z * s.userAcceleration.z
        }
        let total = ex + ey + ez
        guard total > 1e-10 else { return Vector3(x: 0.33, y: 0.33, z: 0.33) }
        return Vector3(x: ex / total, y: ey / total, z: ez / total)
    }

    /// Extract a full ContinuousGestureProfile from training samples.
    static func extractProfile(from samples: [MotionSample], sampleRate: Double = 100.0) -> ContinuousGestureProfile {
        let freq = dominantFrequency(from: samples, sampleRate: sampleRate)
        let bandEnergies = frequencyBandEnergies(from: samples, sampleRate: sampleRate)
        let axisDist = axisEnergyDistribution(from: samples)

        let amplitudes = samples.map { $0.userAcceleration.magnitude }
        let ampMin = amplitudes.min() ?? 0
        let ampMax = amplitudes.max() ?? 0

        return ContinuousGestureProfile(
            dominantFrequency: freq,
            frequencyBandEnergy: bandEnergies,
            axisDistribution: axisDist,
            amplitudeMin: ampMin,
            amplitudeMax: ampMax
        )
    }

    /// Average multiple profiles (from multiple training recordings).
    static func averageProfiles(_ profiles: [ContinuousGestureProfile]) -> ContinuousGestureProfile? {
        guard !profiles.isEmpty else { return nil }
        let n = Double(profiles.count)

        let avgFreq = profiles.map(\.dominantFrequency).reduce(0, +) / n

        let bandCount = profiles[0].frequencyBandEnergy.count
        var avgBands = [Double](repeating: 0, count: bandCount)
        for p in profiles {
            for (i, e) in p.frequencyBandEnergy.enumerated() where i < bandCount {
                avgBands[i] += e
            }
        }
        avgBands = avgBands.map { $0 / n }

        let avgAxis = Vector3(
            x: profiles.map(\.axisDistribution.x).reduce(0, +) / n,
            y: profiles.map(\.axisDistribution.y).reduce(0, +) / n,
            z: profiles.map(\.axisDistribution.z).reduce(0, +) / n
        )

        let ampMin = profiles.map(\.amplitudeMin).min() ?? 0
        let ampMax = profiles.map(\.amplitudeMax).max() ?? 0

        return ContinuousGestureProfile(
            dominantFrequency: avgFreq,
            frequencyBandEnergy: avgBands,
            axisDistribution: avgAxis,
            amplitudeMin: ampMin,
            amplitudeMax: ampMax
        )
    }

    // MARK: - FFT Internals

    private static func dominantFrequencyFromSignal(_ signal: [Double], sampleRate: Double) -> Double {
        let spectrum = fftMagnitudeSpectrum(signal)
        guard spectrum.count > 1 else { return 0 }

        // Skip DC component (index 0) and find peak
        var maxMag = 0.0
        var maxIndex = 1
        for i in 1..<spectrum.count {
            if spectrum[i] > maxMag {
                maxMag = spectrum[i]
                maxIndex = i
            }
        }

        let freqResolution = sampleRate / Double(nextPowerOf2(signal.count))
        return Double(maxIndex) * freqResolution
    }

    private static func fftMagnitudeSpectrum(_ signal: [Double]) -> [Double] {
        let n = signal.count
        guard n >= 4 else { return [] }

        let fftSize = nextPowerOf2(n)
        let log2n = vDSP_Length(log2(Double(fftSize)))

        guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetupD(fftSetup) }

        // Pad signal to power of 2, remove DC offset
        var paddedSignal = [Double](repeating: 0, count: fftSize)
        let mean = signal.reduce(0, +) / Double(n)
        for i in 0..<n {
            paddedSignal[i] = signal[i] - mean
        }

        // Apply Hann window
        var window = [Double](repeating: 0, count: fftSize)
        vDSP_hann_windowD(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmulD(paddedSignal, 1, window, 1, &paddedSignal, 1, vDSP_Length(fftSize))

        // Split complex format
        let halfN = fftSize / 2
        var realPart = [Double](repeating: 0, count: halfN)
        var imagPart = [Double](repeating: 0, count: halfN)

        paddedSignal.withUnsafeBufferPointer { inputPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPDoubleSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    inputPtr.baseAddress!.withMemoryRebound(to: DSPDoubleComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctozD(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                    vDSP_fft_zripD(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }
        }

        // Compute magnitude spectrum
        var magnitudes = [Double](repeating: 0, count: halfN)
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPDoubleSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )
                vDSP_zvmagsD(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Convert to root magnitude
        for i in 0..<halfN {
            magnitudes[i] = magnitudes[i].squareRoot()
        }

        return magnitudes
    }

    private static func nextPowerOf2(_ n: Int) -> Int {
        var p = 1
        while p < n { p *= 2 }
        return p
    }
}
