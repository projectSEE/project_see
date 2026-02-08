import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Exports conversations as formatted PDF documents.
class ConversationExporter {
  ConversationExporter._();

  /// Export and share conversation as PDF
  static Future<void> exportAsPdf(
    List<Map<String, dynamic>> messages, {
    String title = 'Visual Assistant Conversation',
  }) async {
    final pdf = _buildDocument(messages, title);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'conversation_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Document _buildDocument(
    List<Map<String, dynamic>> messages,
    String title,
  ) {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildHeader(title),
        footer: (context) => _buildFooter(context),
        build: (context) => _buildMessages(messages),
      ),
    );

    return pdf;
  }

  static pw.Widget _buildHeader(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Exported: ${DateTime.now().toString().substring(0, 16)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Divider(thickness: 2),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
      ),
    );
  }

  static List<pw.Widget> _buildMessages(List<Map<String, dynamic>> messages) {
    return messages.map((msg) {
      final role = msg['role'] ?? 'unknown';
      final text = msg['text'] ?? '';
      final hasImage = msg['imageBytes'] != null;

      final config = _getRoleConfig(role);

      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: config.bgColor,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: config.borderColor, width: 1),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              config.label,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: config.borderColor,
              ),
            ),
            pw.SizedBox(height: 6),
            if (hasImage)
              pw.Text(
                '[Image attached]',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey600,
                ),
              ),
            if (text.isNotEmpty)
              pw.Text(text, style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      );
    }).toList();
  }

  static _RoleConfig _getRoleConfig(String role) {
    switch (role) {
      case 'user':
        return _RoleConfig('You', PdfColors.blue700, PdfColors.blue50);
      case 'model':
        return _RoleConfig('Assistant', PdfColors.green700, PdfColors.green50);
      case 'system':
        return _RoleConfig('System', PdfColors.grey700, PdfColors.grey200);
      default:
        return _RoleConfig(role, PdfColors.black, PdfColors.white);
    }
  }
}

class _RoleConfig {
  final String label;
  final PdfColor borderColor;
  final PdfColor bgColor;

  _RoleConfig(this.label, this.borderColor, this.bgColor);
}
