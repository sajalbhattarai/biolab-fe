/**
 * Reads TSV, CSV, GFF and Excel files into one table shape for the file viewer,
 * caches them, and serves sorted, filtered pages using the shared rules in
 * lib/workspace/viewers/table-query.ts.
 */

import fs from 'node:fs';
import path from 'node:path';
import ExcelJS from 'exceljs';
import { FileError, resolveRead } from './files';
import {
	TABLE_EXT,
	parseDelimited,
	queryLoaded,
	type CellStyle,
	type Sheet,
	type Table,
	type TableQuery
} from '$lib/workspace/viewers/table-query';
import { sheetsOf } from '$lib/workspace/viewers/excel-sheets';

export type { ColumnInfo, ColumnKind, CellStyle, TableQuery } from '$lib/workspace/viewers/table-query';

const MAX_BYTES = 200 * 1024 * 1024;

export const isTableFile = (p: string) => path.extname(p).toLowerCase() in TABLE_EXT;

// ---------------------------------------------------------------- reading

function readDelimited(abs: string, kind: 'tsv' | 'csv' | 'gff'): Sheet {
	return parseDelimited(fs.readFileSync(abs, 'utf8'), kind, path.basename(abs));
}

async function readExcel(abs: string, palette: CellStyle[]): Promise<Sheet[]> {
	const wb = new ExcelJS.Workbook();
	await wb.xlsx.readFile(abs);
	return sheetsOf(wb, palette);
}

// ---------------------------------------------------------------- cache

const cache = new Map<string, { key: string; table: Table }>();

async function load(abs: string): Promise<Table> {
	const st = fs.statSync(abs);
	if (st.isDirectory()) throw new FileError('That is a folder.', 400);
	if (st.size > MAX_BYTES) throw new FileError('Too large to show as a table. Download it instead.', 413);
	const key = `${st.mtimeMs}:${st.size}`;
	const hit = cache.get(abs);
	if (hit?.key === key) {
		cache.delete(abs);
		cache.set(abs, hit); // most recently used last
		return hit.table;
	}
	const kind = TABLE_EXT[path.extname(abs).toLowerCase()];
	if (!kind) throw new FileError('Not a table file.', 400);
	const palette: CellStyle[] = [];
	const sheets = kind === 'xlsx' ? await readExcel(abs, palette) : [readDelimited(abs, kind)];
	const table: Table = { kind, sheets, palette };
	cache.set(abs, { key, table });
	while (cache.size > 4) cache.delete(cache.keys().next().value as string);
	return table;
}

// ---------------------------------------------------------------- query

export async function queryTable(p: string, query: TableQuery) {
	const abs = resolveRead(p);
	if (!fs.existsSync(abs)) throw new FileError(`Not found: ${abs}`, 404);
	return queryLoaded(await load(abs), query, { path: abs, name: path.basename(abs) });
}
