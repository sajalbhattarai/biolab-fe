/**
 * Cluster-only parts of the interface (see backend.svelte.ts).
 * margie-pipeline's GUI has its own copy of this file with none.
 */

import type { Component } from 'svelte';
import ClusterSetup from '$lib/cluster/ClusterSetup.svelte';
import { chatLink, chatRemote } from '$lib/cluster/backend';
import ComputeToggle from '$lib/cluster/ComputeToggle.svelte';

/** A genome's cluster results as genome chat reads them (lib/server/genome-chat's Remote). */
export interface ChatRemote {
	api: string;
	token: string;
	roots: string[];
	table?: string | null;
	jobs?: { id: string; dir: string }[];
}

/** Stops the HPC tunnel and server via /api/connect; cluster runs keep going. */
async function disconnect(): Promise<boolean> {
	try {
		const r = await fetch('/api/connect', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ action: 'hpc-stop' })
		});
		return r.ok;
	} catch {
		return false;
	}
}

export const clusterParts: {
	Setup?: Component;
	/** Where to choose between this computer and the cluster (the start page). */
	switchHref?: string;
	/** Disconnects from the cluster. */
	disconnect?: () => Promise<boolean>;
	/** Endpoint that keeps and checks the Install page's lock, in both modes. */
	lockApi: string;
	/** Genome chat for cluster results: served locally (the key stays here), reading results through the tunnel. */
	chat?: { url: string; remote: (genome: string) => Promise<ChatRemote | null>; link?: () => { api: string; token: string } | null };
	/** Header control in HPC mode choosing where the server runs (login or compute node). */
	Compute?: Component;
} = { Compute: ComputeToggle, Setup: ClusterSetup, switchHref: '/start', disconnect, lockApi: '/api/local/install-lock', chat: { url: '/api/local/genome-chat', remote: chatRemote, link: chatLink } };
