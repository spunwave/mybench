#include "mybench/help.h"

#include <QColor>
#include <QDir>
#include <QFont>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>
#include <QTextFrame>
#include <QTextTable>
#include <QFile>
#include <QJSEngine>
#include <QRegularExpression>
#include <QUrl>
#include <QVariantMap>

#include <functional>

using namespace Qt::StringLiterals;

namespace mybench {

namespace {

const QString kHelpRoot = u":/mybench/help"_s;

}  // namespace

Help::Help(QObject* parent) : QObject(parent) {}

Help* Help::instance()
{
    static Help* const help = new Help;
    return help;
}

Help* Help::create(QQmlEngine*, QJSEngine*)
{
    Help* help = instance();
    QJSEngine::setObjectOwnership(help, QJSEngine::CppOwnership);
    return help;
}

QString Help::resourcePath(const QString& id)
{
    return kHelpRoot + u'/' + id + u".md"_s;
}

bool Help::has(const QString& id) const
{
    return !id.isEmpty() && QFile::exists(resourcePath(id));
}

QString Help::markdown(const QString& id) const
{
    QFile file(resourcePath(id));
    if (id.isEmpty() || !file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    return QString::fromUtf8(file.readAll());
}

QString Help::html(const QString& id, const QVariantMap& style) const
{
    QString text = markdown(id);
    if (text.isEmpty())
        text = u"# %1\n\n%2"_s.arg(title(id), tr("No help page"));
    // The page title is the first "# " line (Help::title, the topic list); the drawer header
    // already shows it, so the rendered page starts with the one-line summary.
    const qsizetype titleAt = text.indexOf(u"# "_s);
    if (titleAt == 0) {
        const qsizetype end = text.indexOf(u'\n');
        text = end < 0 ? QString() : text.mid(end + 1).trimmed();
    }
    return renderMarkdown(text, style);
}

QString Help::renderMarkdown(const QString& markdown, const QVariantMap& style)
{
    auto color = [&](const char* key, const char* fallback) {
        const QColor c(style.value(QString::fromLatin1(key)).toString());
        return c.isValid() ? c : QColor(QString::fromLatin1(fallback));
    };
    const QColor text = color("text", "#E7E9EE");
    const QColor heading = color("heading", "#FFFFFF");
    const QColor muted = color("muted", "#A1A7B3");
    const QColor accent = color("accent", "#6D8BFF");
    const QColor border = color("border", "#323641");
    const QColor code = color("codeBackground", "#0E0F13");
    const QColor headerFill = color("tableHeader", "#1B1F2A");
    const QColor chipFill = color("chip", "#232733");
    const QColor chipText = color("chipText", "#E7E9EE");
    const int body = style.value(u"bodySize"_s, 13).toInt();

    QTextDocument document;
    QFont font = document.defaultFont();
    font.setPixelSize(body);
    document.setDefaultFont(font);
    document.setIndentWidth(14);
    document.setMarkdown(markdown, QTextDocument::MarkdownDialectGitHub);

    QTextCursor cursor(&document);
    for (QTextBlock block = document.begin(); block.isValid(); block = block.next()) {
        QTextBlockFormat format = block.blockFormat();
        QTextCharFormat chars;
        const int level = format.headingLevel();
        if (level > 0) {
            static constexpr int kSizes[] = {19, 15, 13, 13, 13, 13};
            format.setTopMargin(block == document.begin() ? 0 : (level <= 2 ? 16 : 10));
            format.setBottomMargin(level == 1 ? 6 : 4);
            QFont headingFont = font;
            headingFont.setPixelSize(kSizes[std::clamp(level, 1, 6) - 1]);
            headingFont.setWeight(QFont::DemiBold);
            chars.setFont(headingFont, QTextCharFormat::FontPropertiesSpecifiedOnly);
            chars.setForeground(level >= 4 ? muted : (level == 1 ? heading : accent));
        } else {
            format.setBottomMargin(6);
            format.setLineHeight(125, QTextBlockFormat::ProportionalHeight);
            chars.setForeground(text);
        }
        if (block.textList())
            format.setBottomMargin(2);
        // Table cells: no paragraph spacing, the cell padding spaces the rows.
        cursor.setPosition(block.position());
        if (cursor.currentTable()) {
            format.setTopMargin(0);
            format.setBottomMargin(0);
            format.setLineHeight(110, QTextBlockFormat::ProportionalHeight);
        }
        const bool codeBlock = format.nonBreakableLines() || format.hasProperty(QTextFormat::BlockCodeFence);
        if (codeBlock) {
            format.setBackground(code);
            format.setLeftMargin(6);
            format.setBottomMargin(0);
            format.setLineHeight(120, QTextBlockFormat::ProportionalHeight);
        }
        cursor.setPosition(block.position());
        cursor.setBlockFormat(format);
        cursor.setPosition(block.position() + block.length() - 1, QTextCursor::KeepAnchor);
        cursor.mergeCharFormat(chars);

        // Inline formats: links in the accent color, inline code on a tinted background.
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const QTextFragment fragment = it.fragment();
            QTextCharFormat f = fragment.charFormat();
            bool changed = false;
            if (f.isAnchor()) {
                f.setForeground(accent);
                f.setFontUnderline(false);
                changed = true;
            }
            if (f.fontFixedPitch() || f.fontFamilies().toStringList().contains(u"monospace"_s)) {
                f.setBackground(chipFill);
                f.setForeground(chipText);
                changed = true;
            }
            if (changed) {
                QTextCursor c(&document);
                c.setPosition(fragment.position());
                c.setPosition(fragment.position() + fragment.length(), QTextCursor::KeepAnchor);
                c.setCharFormat(f);
            }
        }
    }

    // Colour with meaning: signal names in their trace colours, Run / Stop (bold, as control names)
    // in the run and stop colours.
    struct Word { const char* pattern; QColor color; bool boldOnly; };
    const Word words[] = {
        {R"(\bAI ?0\b|\bCH ?0\b|\bAudio L\b(?! out))", color("ch0", "#4CC38A"), false},
        {R"(\bAI ?1\b|\bCH ?1\b|\bAudio R\b(?! out))", color("ch1", "#3FB8E0"), false},
        {R"(\bAO ?0\b|\bAudio L out\b)", color("ao0", "#F2994A"), false},
        {R"(\bAO ?1\b|\bAudio R out\b)", color("ao1", "#E26FC0"), false},
        {R"(\bMath\b)", color("math", "#E8C547"), false},
        {R"(\bRef\b)", color("ref", "#A78BFA"), false},
        {R"(\bRun\b)", color("run", "#2EA043"), true},
        {R"(\bStop\b)", color("stop", "#F85149"), true},
    };
    for (const Word& word : words) {
        const QRegularExpression re(QString::fromLatin1(word.pattern));
        QTextCursor found = document.find(re, 0, QTextDocument::FindCaseSensitively);
        while (!found.isNull()) {
            QTextCursor probe(&document);
            probe.setPosition(found.selectionStart() + 1);
            const QTextCharFormat current = probe.charFormat();
            if (!current.isAnchor() && (!word.boldOnly || current.fontWeight() >= QFont::DemiBold)) {
                QTextCharFormat f;
                f.setForeground(word.color);
                found.mergeCharFormat(f);
            }
            found = document.find(re, found, QTextDocument::FindCaseSensitively);
        }
    }

    // Tables: no grid (the rich-text view draws no per-cell rules), banded rows, header on the tint.
    std::function<void(QTextFrame*)> styleFrames = [&](QTextFrame* frame) {
        for (QTextFrame* child : frame->childFrames()) {
            if (auto* table = qobject_cast<QTextTable*>(child)) {
                QTextTableFormat format = table->format();
                format.setBorder(0);
                format.setBorderCollapse(true);
                format.setCellPadding(4);
                format.setCellSpacing(0);
                format.setTopMargin(4);
                format.setBottomMargin(8);
                format.setWidth(QTextLength(QTextLength::PercentageLength, 100));
                table->setFormat(format);
                for (int row = 0; row < table->rows(); ++row) {
                    for (int column = 0; column < table->columns(); ++column) {
                        QTextTableCell cell = table->cellAt(row, column);
                        QTextTableCellFormat cf = cell.format().toTableCellFormat();
                        if (row == 0)
                            cf.setBackground(headerFill);
                        else if (row % 2 == 0)
                            cf.setBackground(code);  // faint banding in place of row rules
                        cell.setFormat(cf);
                        // Header row and the first column (control names): DemiBold.
                        if (row == 0 || column == 0) {
                            QTextCursor c = cell.firstCursorPosition();
                            c.setPosition(cell.lastCursorPosition().position(), QTextCursor::KeepAnchor);
                            QTextCharFormat weight;
                            weight.setFontWeight(QFont::DemiBold);
                            c.mergeCharFormat(weight);
                        }
                    }
                }
            }
            styleFrames(child);
        }
    };
    styleFrames(document.rootFrame());
    return document.toHtml();
}

QString Help::title(const QString& id) const
{
    QFile file(resourcePath(id));
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (!file.atEnd()) {
            const QString line = QString::fromUtf8(file.readLine()).trimmed();
            if (line.startsWith(u"# "_s))
                return line.mid(2).trimmed();
        }
    }
    return id;
}

QString Help::topicForLink(const QString& link) const
{
    const QUrl url(link);
    if (!url.scheme().isEmpty() && url.scheme() != u"file"_s && url.scheme() != u"qrc"_s)
        return {};
    QString path = url.path();
    if (!path.endsWith(u".md"_s))
        return {};
    const QString id = path.section(u'/', -1).chopped(3);
    return has(id) ? id : QString();
}

QVariantList Help::topics() const
{
    QStringList ids;
    const QStringList files = QDir(kHelpRoot).entryList({u"*.md"_s}, QDir::Files, QDir::Name);
    for (const QString& file : files)
        ids.append(file.chopped(3));
    if (ids.removeOne(u"app"_s))
        ids.prepend(u"app"_s);
    QVariantList list;
    for (const QString& id : std::as_const(ids)) {
        QVariantMap topic;
        topic.insert(u"id"_s, id);
        topic.insert(u"title"_s, title(id));
        list.append(topic);
    }
    return list;
}

}  // namespace mybench
