import { json } from '@sveltejs/kit';
import { getTools } from '$lib/server/pipeline';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async () => json(getTools());
