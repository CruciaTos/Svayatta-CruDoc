"""Tests for rebuilding a bill's table from PaddleOCR's text boxes.

    .venv\\Scripts\\python.exe -m unittest test_bill_scan
"""

import math
import unittest

import bill_scan


def cell(text, x, y, w=None, h=20):
    w = w or 12 * len(text)
    return {"text": text, "x1": x, "y1": y, "x2": x + w, "y2": y + h}


HEADER_X = {"Sr": 60, "Product": 120, "Pack": 560, "Batch": 690, "Expiry": 820,
            "Qty": 980, "Free": 1100, "MRP": 1220, "Rate": 1360, "Amount": 1500}


def table_row(y, values):
    return [cell(v, x, y) for v, x in zip(values, HEADER_X.values())]


BILL = [
    cell("SHREE GANESH PHARMA DISTRIBUTORS", 60, 40, h=40),
    cell("TAX INVOICE", 1180, 40, h=36),
    cell("Invoice No: SGPD/2026/04512", 1180, 95),
    cell("Date: 14/10/2026", 1180, 130),
    *[cell(t, x, 255) for t, x in HEADER_X.items()],
    *table_row(310, ["1", "DOLO 650 TAB", "15'S", "DL24A91", "03/28", "10", "1", "33.60", "24.10", "241.00"]),
    *table_row(362, ["2", "PANTOCID 40MG TAB", "10'S", "PT77812", "09/27", "6", "0", "155.00", "112.40", "674.40"]),
    cell("Sub Total", 1100, 450),
    cell("2450.10", 1500, 450),
]


class ParseBill(unittest.TestCase):
    def test_reads_the_table_under_its_header(self):
        bill = bill_scan.parse_bill(bill_scan.group_rows(BILL))
        self.assertEqual(bill["supplier"], "SHREE GANESH PHARMA DISTRIBUTORS")
        self.assertEqual(bill["invoiceNumber"], "SGPD/2026/04512")
        self.assertEqual(bill["invoiceDate"], "14/10/2026")
        self.assertEqual(len(bill["items"]), 2, "totals aren't items")
        first = bill["items"][0]
        self.assertEqual(first["name"], "DOLO 650 TAB", "the serial number stays out")
        self.assertEqual(first["pack"], "15'S")
        self.assertEqual(first["batch"], "DL24A91")
        self.assertEqual(first["expiry"], "03/28")
        self.assertEqual(first["quantity"], 10)
        self.assertEqual(first["freeQuantity"], 1)
        self.assertEqual(first["mrp"], 33.6)
        self.assertEqual(first["rate"], 24.1)
        self.assertEqual(first["amount"], 241)

    def test_unkept_columns_take_their_own_text(self):
        header = [cell("Product", 100, 0), cell("HSN", 400, 0), cell("Batch", 600, 0),
                  cell("Qty", 800, 0), cell("GST%", 900, 0), cell("Rate", 1000, 0)]
        row = [cell("PAN 40 TAB", 100, 40), cell("30049099", 400, 40), cell("PN112", 600, 40),
               cell("5", 800, 40), cell("12", 900, 40), cell("58.00", 1000, 40)]
        item = bill_scan.parse_bill(bill_scan.group_rows(header + row))["items"][0]
        self.assertEqual(item["batch"], "PN112")
        self.assertEqual(item["quantity"], 5)
        self.assertEqual(item["rate"], 58)

    def test_without_a_header_rows_with_an_expiry_are_items(self):
        rows = [cell("AZITHRAL 500 TAB", 50, 100), cell("AZ7731", 400, 100), cell("08/27", 550, 100),
                cell("Thank you", 50, 300)]
        items = bill_scan.parse_bill(bill_scan.group_rows(rows))["items"]
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["name"], "AZITHRAL 500 TAB")
        self.assertEqual(items[0]["batch"], "AZ7731")
        self.assertEqual(items[0]["expiry"], "08/27")


class Totals(unittest.TestCase):
    def test_discount_tax_and_two_line_headings(self):
        # The test invoice's table: "Disc." over "(%)", "Taxable Value".
        cols = {"Sr.": 20, "Name of Product": 70, "Batch No": 225, "Expiry Date": 345,
                "HSN / SAC": 410, "Qty": 490, "MRP": 540, "Rate": 590, "Disc.": 665, "Taxable Value": 730}
        rows = [cell("MediCare", 160, 20, h=30), cell("Wholesale Pharmacy", 160, 55, h=30),
                cell("Invoice Date 13-Dec-2024", 600, 120)]
        edges = [*cols.values(), 800]
        rows += [cell(t, x, 400, w=min(12 * len(t), edges[i + 1] - x - 8))
                 for i, (t, x) in enumerate(cols.items())]
        rows += [cell("(%)", 670, 422)]
        values = ["1", "Paracetamol 500 mg", "A1", "Dec 2026", "30045031", "10 TBS", "50.00", "40.00", "10.00", "360.00"]
        rows += [cell(v, x, 440, w=min(12 * len(v), edges[i + 1] - x - 8))
                 for i, (v, x) in enumerate(zip(values, cols.values()))]
        rows += [cell("IGST (12.00 %)", 70, 520), cell("Total", 440, 640), cell("40", 490, 640),
                 cell("245.00", 665, 640), cell("₹ 2,469.60", 730, 640),
                 cell("TWO THOUSAND FOUR HUNDRED AND SIXTY-NINE RUPEES AND SIXTY PAISA ONLY", 30, 690)]
        bill = bill_scan.parse_bill(bill_scan.group_rows(rows))
        self.assertEqual(bill["supplier"], "MediCare Wholesale Pharmacy")
        self.assertEqual(bill["invoiceDate"], "13-Dec-2024")
        self.assertEqual(bill["grandTotal"], 2469.6)
        self.assertEqual(bill["taxPercent"], 12)
        item = bill["items"][0]
        self.assertEqual(item["name"], "Paracetamol 500 mg")
        self.assertEqual(item["discountPercent"], 10)
        self.assertEqual(item["rate"], 40)
        self.assertEqual(item["amount"], 360, '"Taxable Value" is the amount')
        self.assertEqual(item["quantity"], 10)
        self.assertEqual(item["quantityUnit"], "TBS")

    def test_cgst_and_sgst_add_up(self):
        totals = bill_scan.bill_totals(["CGST 6% 147.01", "SGST 6% 147.01", "Grand Total 2744.12"])
        self.assertEqual(totals, {"grandTotal": 2744.12, "taxPercent": 12})


class Rows(unittest.TestCase):
    def test_cells_on_one_line_share_a_row(self):
        rows = bill_scan.group_rows([cell("b", 300, 102), cell("a", 10, 100), cell("c", 10, 160)])
        self.assertEqual([[c["text"] for c in r] for r in rows], [["a", "b"], ["c"]])

    def test_tilt_is_the_slope_of_the_text(self):
        a = math.radians(4)
        poly = [(0, 0), (200 * math.cos(a), 200 * math.sin(a)),
                (200 * math.cos(a) - 20 * math.sin(a), 200 * math.sin(a) + 20 * math.cos(a)),
                (-20 * math.sin(a), 20 * math.cos(a))]
        self.assertAlmostEqual(bill_scan.tilt([poly]), a, places=3)


class Values(unittest.TestCase):
    def test_numbers(self):
        self.assertEqual(bill_scan.to_number("₹1,250.50"), 1250.5)
        self.assertEqual(bill_scan.to_number("Rs. 40"), 40)
        self.assertIsNone(bill_scan.to_number("—"))
        self.assertEqual(bill_scan.to_number(7), 7)

    def test_an_item_has_every_field(self):
        item = bill_scan.clean_item({"name": "  DOLO  650 ", "quantity": "10"})
        self.assertEqual(set(item), set(bill_scan.ITEM_FIELDS))
        self.assertEqual(item["name"], "DOLO 650")
        self.assertEqual(item["quantity"], 10)
        self.assertIsNone(item["batch"])


if __name__ == "__main__":
    unittest.main()
