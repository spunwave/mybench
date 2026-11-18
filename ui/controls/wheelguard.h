// WheelGuard: native wheel etiquette for controls inside scrollable views (QML singleton).
// A control reacts to the wheel only when focused or when the gesture starts over it; a scroll that
// merely passes over it keeps scrolling the view. Call `WheelGuard.allows(hasFocus)` from a wheel
// handler, or bind `WheelGuard.freshGesture` to the handler's `enabled`.
#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QtQml/qqmlregistration.h>

namespace mybench {

class WheelGuard : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int gestureGap READ gestureGap WRITE setGestureGap NOTIFY gestureGapChanged)
    // Bind a WheelHandler's `enabled` to freshGesture: it flips before the wheel event is delivered,
    // and a disabled handler lets the event through to the scrolling view underneath.
    Q_PROPERTY(bool freshGesture READ startsGesture NOTIFY freshGestureChanged)

public:
    explicit WheelGuard(QObject* parent = nullptr);

    Q_INVOKABLE bool startsGesture() const { return m_fresh; }
    Q_INVOKABLE bool allows(bool hasFocus) const { return hasFocus || m_fresh; }

    int gestureGap() const { return m_gap; }
    void setGestureGap(int ms);

signals:
    void gestureGapChanged();
    void freshGestureChanged();
    // Emitted for every wheel event that starts a gesture: controls that keep the rest of a gesture
    // they started reset their ownership here.
    void gestureStarted();

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    QElapsedTimer m_last;
    void setFresh(bool fresh);
    bool m_fresh = true;
    int m_gap = 350;
};

}  // namespace mybench
