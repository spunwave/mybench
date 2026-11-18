// The native backend's error messages are the app's own words: they reach the screen (pane
// banners, the Event Log), so they never name the driver library.
#include "usb/usb_device.h"

#include <QtTest>

using namespace mydaq;

class TestUsbErrors : public QObject {
    Q_OBJECT

private slots:
    void messagesNameNoLibrary()
    {
        for (int rc = MYDAQ_OK; rc >= MYDAQ_ERR_FIRMWARE - 1; --rc) {
            const QString message = usb::errorMessage(rc);
            QVERIFY2(!message.isEmpty(), qPrintable(QString::number(rc)));
            QVERIFY2(!message.contains(QStringLiteral("libmydaq"), Qt::CaseInsensitive), qPrintable(message));
            QVERIFY2(!message.contains(QStringLiteral("(yet)")), qPrintable(message));
            if (rc == MYDAQ_OK)
                continue;
            try {
                usb::raise(rc, QStringLiteral("Open"));
                QFAIL("raise returned");
            } catch (const DeviceError& e) {
                QCOMPARE(QString::fromUtf8(e.what()), QStringLiteral("Open: ") + message);
            }
        }
    }
    void codesKeepTheirKind()
    {
        const auto codeOf = [](int rc) {
            try {
                usb::raise(rc, QStringLiteral("x"));
            } catch (const DeviceError& e) {
                return e.code();
            }
            return DeviceError::Generic;
        };
        QCOMPARE(codeOf(MYDAQ_ERR_NOT_SUPPORTED), DeviceError::NotSupported);
        QCOMPARE(codeOf(MYDAQ_ERR_ACCESS), DeviceError::AccessDenied);
        QCOMPARE(codeOf(MYDAQ_ERR_BUSY), DeviceError::ResourceBusy);
    }
};

QTEST_GUILESS_MAIN(TestUsbErrors)
#include "tst_usberrors.moc"
