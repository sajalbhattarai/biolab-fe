/**
 * Converts a parsed Excel workbook into the file viewer's sheets, keeping each
 * cell's fill, text colour, bold and borders in a shared palette.
 */

import type ExcelJS from 'exceljs';
import { describe, type CellStyle, type Sheet } from './table-query';

const argb = (c: { argb?: string } | undefined) => (c?.argb && /^[0-9A-F]{8}$/i.test(c.argb) ? `#${c.argb.slice(2)}` : undefined);

export function sheetsOf(wb: ExcelJS.Workbook, palette: CellStyle[]): Sheet[] {
	const index = new Map<string, number>();
	const styleOf = (cell: ExcelJS.Cell): number => {
		const fill = cell.fill?.type === 'pattern' && cell.fill.pattern === 'solid' ? argb(cell.fill.fgColor) : undefined;
		const b = cell.border;
		const heavy = (e?: Partial<ExcelJS.Border>) => !!e?.style && e.style !== 'hair';
		const border = b ? ['t', 'r', 'b', 'l'].filter((_, i) => heavy([b.top, b.right, b.bottom, b.left][i])).join('') : '';
		const s: CellStyle = { bg: fill, fg: argb(cell.font?.color), bold: cell.font?.bold || undefined, border: border || undefined };
		if (!s.bg && !s.fg && !s.bold && !s.border) return -1;
		const key = JSON.stringify(s);
		let i = index.get(key);
		if (i === undefined) {
			i = palette.push(s) - 1;
			index.set(key, i);
		}
		return i;
	};

	const sheets: Sheet[] = [];
	wb.eachSheet((ws) => {
		const width = ws.actualColumnCount || ws.columnCount;
		const all: string[][] = [];
		const styles: Int32Array[] = [];
		ws.eachRow({ includeEmpty: false }, (row) => {
			const cells: string[] = [];
			const st = new Int32Array(width).fill(-1);
			for (let c = 1; c <= width; c++) {
				const cell = row.getCell(c);
				cells.push(cell.text ?? '');
				st[c - 1] = styleOf(cell);
			}
			all.push(cells);
			styles.push(st);
		});
		const header = all.shift() ?? [];
		const headerStyles = styles.shift();
		const names = Array.from({ length: width }, (_, i) => header[i]?.trim() || `Column ${i + 1}`);
		const columns = describe(names, all);
		columns.forEach((col, i) => {
			const w = ws.getColumn(i + 1).width;
			if (w) col.width = Math.round(Math.min(60, w) * 7 + 12);
		});
		const view = ws.views?.[0] as { state?: string; xSplit?: number } | undefined;
		const hs = headerStyles?.find((i) => i >= 0);
		sheets.push({
			name: ws.name,
			columns,
			rows: all,
			styles,
			headerStyle: hs !== undefined ? palette[hs] : undefined,
			frozen: view?.state === 'frozen' ? view.xSplit : undefined
		});
	});
	return sheets;
}
