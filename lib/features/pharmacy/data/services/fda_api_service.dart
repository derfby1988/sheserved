import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class FdaDrugModel {
  final String productNameThai;
  final String productNameEng;
  final String licenseNo;
  final String manufacturer;
  final String categoryThai; // thaclassnm (e.g. ยาใช้ภายใน)
  final String riskStatusThai; // thakindnm (e.g. ยาสามัญประจำบ้าน)
  final String registrationStatus; // cncnm (e.g. คงอยู่, ยกเลิก)

  FdaDrugModel({
    required this.productNameThai,
    required this.productNameEng,
    required this.licenseNo,
    required this.manufacturer,
    required this.categoryThai,
    required this.riskStatusThai,
    required this.registrationStatus,
  });

  // map riskStatusThai to fdaRiskStatus code (e.g. ND, D, S)
  String? get fdaRiskStatusCode {
    switch (riskStatusThai) {
      case 'ยาสามัญประจำบ้าน':
        return 'ND';
      case 'ยาอันตราย':
        return 'D';
      case 'ยาควบคุมพิเศษ':
        return 'S';
      case 'ยาเสพติดให้โทษ':
        return 'N';
      case 'วัตถุออกฤทธิ์ต่อจิตและประสาท':
        return 'P';
      default:
        return null; // For others, it might be unclassified or different
    }
  }
}

class FdaApiService {
  static const String _url = 'https://porta.fda.moph.go.th/FDA_SEARCH_ALL/WS_LICENSE_SEARCH.asmx';

  /// ค้นหาข้อมูลยาจากฐานข้อมูล อย. (FDA Open API)
  Future<List<FdaDrugModel>> searchDrugs(String keyword) async {
    final soapEnvelope = '''<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <GET_DATA_ALL xmlns="http://tempuri.org/">
      <DATAS>${keyword.trim()}</DATAS>
    </GET_DATA_ALL>
  </soap:Body>
</soap:Envelope>''';

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPAction': '"http://tempuri.org/GET_DATA_ALL"',
        },
        body: soapEnvelope,
      );

      if (response.statusCode == 200) {
        return _parseSoapResponse(response.body);
      } else {
         throw Exception('FDA API ยิงไม่สำเร็จ Status: ${response.statusCode}');
      }
    } catch (e) {
       throw Exception('เกิดข้อผิดพลาดในการเชื่อมต่อ อย.: $e');
    }
  }

  List<FdaDrugModel> _parseSoapResponse(String responseBody) {
    List<FdaDrugModel> drugModels = [];
    try {
      final document = XmlDocument.parse(responseBody);
      // The inner XML string is embedded inside GET_DATA_ALLResult
      final resultNodes = document.findAllElements('GET_DATA_ALLResult');
      
      if (resultNodes.isEmpty) return [];

      // XML is structured with an inner string that holds a DiffGram
      String innerXml = resultNodes.first.innerText;
      
      if (innerXml.isEmpty) return [];

      final innerDoc = XmlDocument.parse(innerXml);
      // Data payload is stored in <Table1> tags
      final tableNodes = innerDoc.findAllElements('Table1');

      for (var node in tableNodes) {
        final productha = node.findElements('productha').isEmpty ? '' : node.findElements('productha').first.innerText;
        final produceng = node.findElements('produceng').isEmpty ? '' : node.findElements('produceng').first.innerText;
        final lcnno = node.findElements('lcnno').isEmpty ? '' : node.findElements('lcnno').first.innerText;
        final thanm = node.findElements('thanm').isEmpty ? '' : node.findElements('thanm').first.innerText;
        final thaclassnm = node.findElements('thaclassnm').isEmpty ? '' : node.findElements('thaclassnm').first.innerText;
        final thakindnm = node.findElements('thakindnm').isEmpty ? '' : node.findElements('thakindnm').first.innerText;
        final cncnm = node.findElements('cncnm').isEmpty ? '' : node.findElements('cncnm').first.innerText;

        drugModels.add(FdaDrugModel(
          productNameThai: productha,
          productNameEng: produceng,
          licenseNo: lcnno,
          manufacturer: thanm,
          categoryThai: thaclassnm,
          riskStatusThai: thakindnm,
          registrationStatus: cncnm,
        ));
      }
    } catch (e) {
       // XML parsing error
       print('Parse XML Error: $e');
    }
    return drugModels;
  }
}
