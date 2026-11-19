// UI tests check that text fits its field, so they need the same font everywhere: the reference
// font here (Noto Sans, subset, SIL OFL 1.1, see OFL.txt) at 12 px instead of whatever font
// each CI runner or desktop provides. Linked into the QML and layout test executables only
// (top-level CMakeLists.txt); the app and the screenshot tool keep the platform font.

#include <QCoreApplication>
#include <QDir>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>

namespace {

void useReferenceFont()
{
    if (!qobject_cast<QGuiApplication*>(QCoreApplication::instance()))
        return;
    QString family;
    const QDir dir(QStringLiteral(MYBENCH_TEST_FONT_DIR));
    for (const QString& file : dir.entryList({QStringLiteral("*.ttf")}, QDir::Files)) {
        const int id = QFontDatabase::addApplicationFont(dir.filePath(file));
        if (id >= 0 && family.isEmpty())
            family = QFontDatabase::applicationFontFamilies(id).value(0);
    }
    if (family.isEmpty()) {
        qWarning("reference test font not found in %s", MYBENCH_TEST_FONT_DIR);
        return;
    }
    QFont font(family);
    font.setPixelSize(12);  // the offscreen default (9 pt at 96 dpi); layout_sweep sets 13 px itself
    font.setHintingPreference(QFont::PreferNoHinting);  // same advances on every font engine
    QGuiApplication::setFont(font);
}

}  // namespace

Q_COREAPP_STARTUP_FUNCTION(useReferenceFont)
