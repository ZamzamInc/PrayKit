//
//  PrayerTimer.swift
//  PrayCore
//
//  Created by Basem Emara on 2022-11-26.
//  Copyright © 2022 Zamzam Inc. All rights reserved.
//

import Foundation.NSCalendar
import Foundation.NSDateInterval
import ZamzamCore

public struct PrayerTimer: Equatable, Codable {
    public let date: Date
    public let type: Prayer
    public let timerType: TimerType
    public let countdownDate: Date
    public let timeRange: ClosedRange<Date>
    public let timeRemaining: TimeInterval
    public let progressRemaining: Double
    public let dangerThreshold: Double
    public let isDangerThreshold: Bool
    public let isJumuah: Bool
    public let localizeAt: Date?
}

public extension PrayerTimer {
    init(
        date: Date,
        currentPrayer: PrayerTime,
        nextPrayer: PrayerTime,
        iqamaTimes: IqamaTimes,
        isIqamaTimerEnabled: Bool,
        stopwatchMinutes: Int,
        preAdhanMinutes: Int,
        calendar: Calendar
    ) {
        var iqamaTime: Date?

        if isIqamaTimerEnabled,
           let currentIqama = iqamaTimes[currentPrayer, using: calendar],
           currentPrayer.dateInterval.start.isIqamaTimer(at: date, iqamaTime: currentIqama) {
            iqamaTime = currentIqama
        }

        let isStopwatchTimer = currentPrayer.dateInterval.start.isStopwatchTimer(at: date, minutes: stopwatchMinutes)
        var countdownDate = isStopwatchTimer ? currentPrayer.dateInterval.start : iqamaTime != nil ? iqamaTime ?? .now : currentPrayer.dateInterval.end
        var countdownLocalizeAt: Date? = date
        var timerType = isStopwatchTimer ? TimerType.stopwatch : iqamaTime != nil ? .iqama : .countdown
        var type = timerType == .countdown ? nextPrayer.type : currentPrayer.type
        let progressRemaining = 1 - currentPrayer.dateInterval.progress(at: date).value
        let dangerThreshold = currentPrayer.dateInterval.dangerThreshold(minutes: preAdhanMinutes)

        if date.isJumuah(using: calendar) {
            if nextPrayer.type == .dhuhr, let khutbaIqama = iqamaTimes[nextPrayer, using: calendar] {
                countdownDate = khutbaIqama
                timerType = .iqama
                type = nextPrayer.type
            } else if currentPrayer.type == .dhuhr {
                if isStopwatchTimer {
                    countdownLocalizeAt = nil
                } else if let khutbaIqama = iqamaTimes[currentPrayer, using: calendar], khutbaIqama.isStopwatchTimer(at: date, minutes: stopwatchMinutes) {
                    countdownDate = khutbaIqama
                    timerType = .stopwatch
                    type = currentPrayer.type
                }
            }
        }

        self.date = date
        self.type = type
        self.timerType = timerType
        self.countdownDate = countdownDate
        self.timeRange = min(date, countdownDate)...max(date, countdownDate)
        self.timeRemaining = countdownDate.timeIntervalSince(date)
        self.progressRemaining = progressRemaining
        self.dangerThreshold = dangerThreshold
        self.isDangerThreshold = progressRemaining <= dangerThreshold
        self.isJumuah = date.isJumuah(using: calendar) && type == .dhuhr
        self.localizeAt = countdownLocalizeAt
    }
}

public extension PrayerTimer {
    init?(
        at date: Date,
        using prayerDay: PrayerDay,
        iqamaTimes: IqamaTimes,
        isIqamaTimerEnabled: Bool,
        stopwatchMinutes: Int,
        preAdhanMinutes: PreAdhanMinutes,
        sunriseAfterIsha: Bool,
        timeZone: TimeZone
    ) {
        guard let currentPrayer = prayerDay.current(at: date),
              let nextPrayer = prayerDay.next(at: date, sunriseAfterIsha: sunriseAfterIsha)
        else {
            return nil
        }

        var calendar = Calendar.current
        calendar.timeZone = timeZone

        self.init(
            date: date,
            currentPrayer: currentPrayer,
            nextPrayer: nextPrayer,
            iqamaTimes: iqamaTimes,
            isIqamaTimerEnabled: isIqamaTimerEnabled,
            stopwatchMinutes: stopwatchMinutes,
            preAdhanMinutes: preAdhanMinutes[currentPrayer.type],
            calendar: calendar
        )
    }
}

public extension PrayerTimer {
    init?(at date: Date, using prayerDay: PrayerDay?, preferences: Preferences) {
        guard let prayerDay else { return nil }

        self.init(
            at: date,
            using: prayerDay,
            iqamaTimes: preferences.iqamaTimes,
            isIqamaTimerEnabled: preferences.isIqamaTimerEnabled,
            stopwatchMinutes: preferences.stopwatchMinutes,
            preAdhanMinutes: preferences.preAdhanMinutes,
            sunriseAfterIsha: preferences.sunriseAfterIsha,
            timeZone: preferences.lastTimeZone
        )
    }
}

// MARK: - Types

public extension PrayerTimer {
    enum TimerType: String, Equatable, Codable {
        case countdown
        case stopwatch
        case iqama
    }
}

// MARK: - Helpers

private extension Date {
    /// Determines if the prayer is within the stopwatch timer threshold with a small buffer.
    func isStopwatchTimer(at date: Date, minutes: Int) -> Bool {
        guard minutes > 0 else { return false }
        return date.isBetween(self - 2, self + .minutes(minutes) - 10)
    }

    /// Determines if the prayer is within the iqama timer threshold with a small buffer.
    func isIqamaTimer(at date: Date, iqamaTime: Date) -> Bool {
        date.isBetween(self - 2, iqamaTime - 10)
    }
}

private extension DateInterval {
    /// Determines if the time is within the danger zone of running out of time.
    func dangerThreshold(minutes: Int) -> Double {
        max(1 - (duration - Double(minutes * 60)) / duration, 0.25)
    }
}
