// Text log of the oscilloscope in the layout of the ELVISmx "Log" TXT file: a header block with the
// channel names, t0 and delta t, then time/value column pairs with absolute timestamps.
// ScopeController::exportTable() passes the header data in DataTable::extra (keys below).
#pragma once

#include <mybench/dataexport.h>

namespace mybench::instruments::scope {

inline constexpr auto kLogStart = "scope.start";        // QDateTime of the first displayed sample
inline constexpr auto kLogInterval = "scope.dt";        // double, s between samples
inline constexpr auto kLogShift = "scope.shift";        // double, s: sub-sample trigger alignment
inline constexpr auto kLogChannels = "scope.channels";  // QVariantList of int: channels with data
inline constexpr auto kLogSkew = "scope.skew";          // QVariantList of double: skew of CH 0, CH 1 (s)

class LogWriter : public TableWriter
{
public:
    QString name() const override;
    QStringList extensions() const override;
    bool write(const DataTable& table, const QStringList& header, QIODevice& out, QString* error) const override;
};

}  // namespace mybench::instruments::scope
