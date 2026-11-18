// ContinuityTone: the Multimeter's continuity beeper, a continuous 1 kHz sine on the computer's
// sound output while the probes are shorted (as ELVISmx does: 44.1 kS/s, 16 bit, stereo, 75 %
// volume). Built on Qt Multimedia when available (MYBENCH_DMM_HAVE_AUDIO); otherwise, with no audio
// output, or on the offscreen platform it is silent and `available()` is false.
#pragma once

#include <QObject>

#include <memory>

namespace mybench::instruments {

class ContinuityTone : public QObject
{
    Q_OBJECT

public:
    explicit ContinuityTone(QObject* parent = nullptr);
    ~ContinuityTone() override;

    // Starts or stops the tone (idempotent; cheap to call on every reading).
    void setActive(bool active);
    bool isActive() const { return m_active; }
    // An audio output could be opened (false before the first setActive(true) is attempted if
    // Qt Multimedia is missing or the platform is offscreen).
    bool available() const;

private:
    struct Private;
    std::unique_ptr<Private> d;
    bool m_active = false;
};

}  // namespace mybench::instruments
