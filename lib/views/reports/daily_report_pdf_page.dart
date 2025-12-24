import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../services/database_helper.dart';

class DailyReportPdfPage extends StatelessWidget {
  final int userId;
  final String userEmail;
  final String dateStr;
  final String displayDate;

  const DailyReportPdfPage({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.dateStr,
    required this.displayDate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vista Previa PDF"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: PdfPreview(
        build: (format) => _generatePdf(format),
        canChangeOrientation: false,
        canChangePageFormat: false,
      ),
    );
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final pdf = pw.Document();

    final expenses = await DatabaseHelper.instance.getExpenses(userId, dateStr);

    double total = expenses.fold(
      0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "Reporte Diario de Gastos",
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      "Gastos DuQuen",
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Usuario: $userEmail"),
                  pw.Text(
                    "Fecha: $displayDate",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                context: context,
                border: null,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue),
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300),
                  ),
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                },
                headers: <String>['Descripción', 'Monto (Bs.)'],
                data: expenses.map((item) {
                  return [
                    item['description'] as String,
                    (item['amount'] as num).toStringAsFixed(2),
                  ];
                }).toList(),
              ),
              pw.Divider(),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(top: 10),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      "TOTAL DEL DÍA:  ",
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      "Bs. ${total.toStringAsFixed(2)}",
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                "Generado automáticamente por la App Gastos DuQuen",
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
