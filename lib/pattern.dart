import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';

/// All sizes in inches.
class P {
  final double x, y;
  const P(this.x, this.y);
}

const measureKeys = ['bust', 'waist', 'shoulder', 'front_len', 'back_len', 'sleeve_round'];
const measureLabels = {
  'bust': 'Bust',
  'waist': 'Waist',
  'shoulder': 'Shoulder (across)',
  'front_len': 'Front length',
  'back_len': 'Back length',
  'sleeve_round': 'Sleeve round (arm)',
};

class Piece {
  final String name, qty;
  final List<P> pts;
  final bool fold;
  final List<List<P>> darts;
  List<P> cut = [];
  double ox = 0, oy = 0, x = 0, y = 0, w = 0, h = 0;
  Piece(this.name, this.pts, this.fold, this.qty, this.darts);
}

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

List<P> bez(P p0, P c, P p1, [int n = 18]) {
  final out = <P>[];
  for (var i = 1; i <= n; i++) {
    final t = i / n, u = 1 - t;
    out.add(P(u * u * p0.x + 2 * u * t * c.x + t * t * p1.x, u * u * p0.y + 2 * u * t * c.y + t * t * p1.y));
  }
  return out;
}

List<P> neckPoints(String style, double depth, double width) {
  final s = P(0, depth), e = P(width, 0);
  if (style == 'v') return [s, e];
  if (style == 'square') return [s, P(width, depth), e];
  return [s, ...bez(s, P(width, depth), e)];
}

List<Piece> draft(Map<String, double> m, Map<String, dynamic> neck, Map<String, dynamic> back,
    Map<String, dynamic> sleeve, double hem) {
  final b = m['bust']!, wst = m['waist']!, sh = m['shoulder']!;
  final fl = m['front_len']! + hem, bl = m['back_len']! + hem;
  final w = b / 4 + 1.5; // half width incl. ease
  final ah = b / 6 + 1.5; // armhole depth
  final wx = wst / 4 + 1.5; // waist half width
  final shx = sh / 2;
  final s = P(shx, 1.0), u = P(w, ah);

  (List<P>, List<List<P>>) body(double length, Map<String, dynamic> nk, double cy, bool front) {
    final wl = math.min(length - 2, ah + 4.5);
    final pts = <P>[...neckPoints('${nk['style']}', _d(nk['depth']), _d(nk['width']))];
    pts.add(s);
    pts.addAll(bez(s, P(shx - 0.4, ah * cy), u));
    pts.addAll([P(wx, wl), P(wx + 0.4, length), P(0, length)]);
    var darts = <List<P>>[];
    if (front) {
      final dd = math.max(1.0, math.min(2.0, (b - wst) / 10));
      final y = ah + 1.0;
      darts = [
        [P(w, y - dd / 2), P(w - 3.5, y), P(w, y + dd / 2)]
      ];
    }
    return (pts, darts);
  }

  final f = body(fl, neck, 0.62, true);
  final k = body(bl, back, 0.55, false);
  final pieces = <Piece>[
    Piece('FRONT', f.$1, true, 'Cut 1 on fold', f.$2),
    Piece('BACK', k.$1, true, 'Cut 1 on fold (add centre seam if back-open)', []),
  ];
  final sl = _d(sleeve['length']);
  if ('${sleeve['style']}' != 'none' && sl > 0) {
    final sw = m['sleeve_round']! / 2 + 1.0;
    final cap = ah / 3 + 0.5;
    final len = sl + hem;
    final p0 = P(0, cap), p1 = P(sw / 2, 0), p2 = P(sw, cap);
    final pts = <P>[p0, ...bez(p0, P(sw * 0.12, 0.1), p1), ...bez(p1, P(sw * 0.88, 0.1), p2), P(sw - 0.5, len), P(0.5, len)];
    pieces.add(Piece('SLEEVE', pts, false, 'Cut 2', []));
  }
  return pieces;
}

/// Seam-allowance outline (mitre offset). Fold edge is clamped to x = 0.
List<P> offsetPoly(List<P> pts, double d, bool fold) {
  final n = pts.length;
  var area = 0.0;
  for (var i = 0; i < n; i++) {
    final a = pts[i], b = pts[(i + 1) % n];
    area += a.x * b.y - b.x * a.y;
  }
  final sgn = area >= 0 ? 1.0 : -1.0;
  P nrm(P a, P b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final l = math.sqrt(dx * dx + dy * dy);
    if (l < 1e-9) return const P(0, 0);
    return P(sgn * dy / l, -sgn * dx / l);
  }

  final out = <P>[];
  for (var i = 0; i < n; i++) {
    final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
    final n1 = nrm(prev, cur), n2 = nrm(cur, next);
    final dot = n1.x * n2.x + n1.y * n2.y;
    final k = d / math.max(0.35, 1 + dot);
    var q = P(cur.x + (n1.x + n2.x) * k, cur.y + (n1.y + n2.y) * k);
    if (fold && q.x < 0) q = P(0, q.y);
    out.add(q);
  }
  return out;
}

/// Packs pieces left-to-right on the fabric width. Returns layout height (in).
double layoutPieces(List<Piece> ps, double fabricW, double seam, [double gap = 1.5]) {
  var x = gap, y = gap, rowh = 0.0;
  for (final p in ps) {
    p.cut = offsetPoly(p.pts, seam, p.fold);
    final minx = p.cut.map((q) => q.x).reduce(math.min), maxx = p.cut.map((q) => q.x).reduce(math.max);
    final miny = p.cut.map((q) => q.y).reduce(math.min), maxy = p.cut.map((q) => q.y).reduce(math.max);
    p.w = maxx - minx;
    p.h = maxy - miny;
    if (x + p.w > fabricW && x > gap) {
      x = gap;
      y += rowh + gap;
      rowh = 0;
    }
    p.ox = x - minx;
    p.oy = y - miny;
    p.x = x;
    p.y = y;
    x += p.w + gap;
    rowh = math.max(rowh, p.h);
  }
  return y + rowh + gap;
}

void _drawSheet(PdfGraphics g, PdfFont f, PdfFont fb, List<Piece> ps, double h, double offx, double offy, double s,
    double seam) {
  for (final p in ps) {
    double X(P q) => offx + (q.x + p.ox) * 72 * s;
    double Y(P q) => offy + (h - (q.y + p.oy)) * 72 * s;
    void path(List<P> pts, bool close) {
      g.moveTo(X(pts[0]), Y(pts[0]));
      for (var i = 1; i < pts.length; i++) {
        g.lineTo(X(pts[i]), Y(pts[i]));
      }
      g.strokePath(close: close);
    }

    g.setStrokeColor(PdfColors.black);
    g.setLineDashPattern();
    g.setLineWidth(1.4);
    path(p.cut, true);
    g.setLineWidth(0.6);
    g.setLineDashPattern([3, 3]);
    path(p.pts, !p.fold);
    for (final d in p.darts) {
      g.moveTo(X(d[0]), Y(d[0]));
      g.lineTo(X(d[1]), Y(d[1]));
      g.lineTo(X(d[2]), Y(d[2]));
      g.strokePath();
    }
    g.setLineDashPattern();
    if (p.fold) {
      final top = P(0, p.pts.map((q) => q.y).reduce(math.min) - seam);
      final bot = P(0, p.pts.map((q) => q.y).reduce(math.max) + seam);
      g.setLineWidth(1);
      g.setLineDashPattern([8, 2, 2, 2]);
      g.moveTo(X(top), Y(top));
      g.lineTo(X(bot), Y(bot));
      g.strokePath();
      g.setLineDashPattern();
      g.drawString(f, 7, 'PLACE ON FOLD', X(top) + 3, Y(top) - 12);
    }
    final cx = p.pts.map((q) => q.x).reduce((a, b) => a + b) / p.pts.length + 0.6;
    final cy = p.pts.map((q) => q.y).reduce((a, b) => a + b) / p.pts.length;
    final c = P(cx, cy);
    g.drawString(fb, 12, p.name, X(c), Y(c));
    g.drawString(f, 7, p.qty, X(c), Y(c) - 11);
    g.drawString(f, 7, 'Solid = cut | Dashed = stitch', X(c), Y(c) - 20);
  }
}

/// Builds the printable PDF: page 1 cutting sheet, then 1:1 pattern tiles on A4.
Future<Uint8List> buildPatternPdf({
  required int orderNo,
  required String name,
  required String phone,
  required String due,
  required String fabric,
  required Map<String, double> m,
  required Map<String, dynamic> neck,
  required Map<String, dynamic> back,
  required Map<String, dynamic> sleeve,
  required double seam,
  required double hem,
  required double fabricW,
}) async {
  final pieces = draft(m, neck, back, sleeve, hem);
  final h = layoutPieces(pieces, fabricW, seam);
  final wIn = pieces.map((p) => p.x + p.w).reduce(math.max) + 1.5;
  final wp = wIn * 72, hp = h * 72;
  final doc = PdfDocument();
  final f = PdfFont.helvetica(doc), fb = PdfFont.helveticaBold(doc);
  const mg = 28.0;
  final pw = PdfPageFormat.a4.width, ph = PdfPageFormat.a4.height;
  final uw = pw - 2 * mg, uh = ph - 2 * mg;

  // ---- page 1: cutting sheet
  var page = PdfPage(doc, pageFormat: PdfPageFormat.a4);
  var g = page.getGraphics();
  g.drawString(fb, 16, 'CUTTING SHEET  -  Order #$orderNo', mg, ph - 40);
  final lines = [
    'Customer: $name    Phone: $phone',
    'Due: $due    Fabric: $fabric',
    'Front neck: ${neck['name']}   Back neck: ${back['name']}   Sleeve: ${sleeve['name']}',
    'Measurements (in): ${measureKeys.map((k) => '${measureLabels[k]} ${m[k]!.toStringAsFixed(m[k]! % 1 == 0 ? 0 : 1)}').join(', ')}',
    'Approx. fabric length (${fabricW.toStringAsFixed(0)} in wide): ${(h / 39.37).toStringAsFixed(2)} m (+ extra for border/lining)',
  ];
  var y = ph - 62;
  for (final l in lines) {
    g.drawString(f, 9, l, mg, y);
    y -= 14;
  }
  final top = y - 6, bottom = 200.0;
  final sc = math.min((pw - 2 * mg) / wp, (top - bottom) / hp);
  _drawSheet(g, f, fb, pieces, h, mg, top - hp * sc, sc, seam);
  g.setStrokeColor(PdfColors.black);
  g.setLineDashPattern();
  g.setLineWidth(1);
  g.drawString(f, 9, 'Scale check: after printing, this box must measure exactly 2 x 2 inches.', mg, 180);
  g.drawRect(mg, 30, 144, 144);
  g.strokePath();
  g.drawString(f, 8, '2 x 2 inch', mg + 4, 34);

  // ---- pattern pages (1:1)
  final cols = (wp / uw).ceil(), rows = (hp / uh).ceil();
  for (var r = 0; r < rows; r++) {
    final b = rows - 1 - r;
    for (var c = 0; c < cols; c++) {
      // skip tiles with no pattern on them
      final tx0 = c * uw, tx1 = (c + 1) * uw, ty0 = b * uh, ty1 = (b + 1) * uh;
      final hit = pieces.any((p) =>
          p.x * 72 < tx1 && (p.x + p.w) * 72 > tx0 && (h - p.y - p.h) * 72 < ty1 && (h - p.y) * 72 > ty0);
      if (!hit) continue;
      page = PdfPage(doc, pageFormat: PdfPageFormat.a4);
      g = page.getGraphics();
      g.saveContext();
      g.drawRect(mg, mg, uw, uh);
      g.clipPath();
      _drawSheet(g, f, fb, pieces, h, mg - c * uw, mg - b * uh, 1.0, seam);
      g.restoreContext();
      g.setStrokeColor(PdfColors.grey600);
      g.setLineWidth(0.3);
      g.setLineDashPattern([1, 2]);
      g.drawRect(mg, mg, uw, uh);
      g.strokePath();
      g.setLineDashPattern();
      g.setStrokeColor(PdfColors.black);
      g.drawString(f, 8, 'Order #$orderNo   Page row ${r + 1}/$rows  col ${c + 1}/$cols   - join pages edge to edge along the dotted border', mg, 12);
    }
  }
  return doc.save();
}
