<script lang="ts">
	import { ChevronDown, ChevronRight } from 'lucide-svelte';

	interface Props {
		title: string;
		description?: string;
		required?: boolean;
		collapsible?: boolean;
		defaultExpanded?: boolean;
		children?: import('svelte').Snippet;
	}

	let {
		title,
		description = '',
		required = false,
		collapsible = true,
		defaultExpanded = false,
		children
	}: Props = $props();

	// Track user toggle state
	let userExpanded = $state<boolean | null>(null);

	// Compute final expanded state: forced (required/non-collapsible) or user preference or default
	let expanded = $derived(
		required || !collapsible ? true : // Force expand if required or not collapsible
		userExpanded !== null ? userExpanded : // Use user preference if set
		defaultExpanded // Otherwise use default
	);

	function toggle() {
		if (collapsible) {
			userExpanded = !expanded;
		}
	}
</script>

<div class="config-section card p-4 mb-4 bg-surface-50 dark:bg-surface-800">
	<button
		type="button"
		class="w-full flex items-center justify-between text-left {collapsible ? 'cursor-pointer' : 'cursor-default'}"
		onclick={toggle}
		disabled={!collapsible}
	>
		<div class="flex-1">
			<h3 class="text-lg font-semibold text-primary-600 dark:text-primary-400">
				{title}
				{#if required}
					<span class="text-error-500 text-sm ml-1">(Required)</span>
				{/if}
			</h3>
			{#if description}
				<p class="text-sm text-surface-600 dark:text-surface-400 mt-1">{description}</p>
			{/if}
		</div>

		{#if collapsible}
			<div class="ml-4">
				{#if expanded}
					<ChevronDown class="size-5 text-surface-600" />
				{:else}
					<ChevronRight class="size-5 text-surface-600" />
				{/if}
			</div>
		{/if}
	</button>

	{#if expanded}
		<div class="mt-4 space-y-2">
			{@render children?.()}
		</div>
	{/if}
</div>

<style>
	.config-section {
		border: 1px solid rgb(var(--color-surface-300));
	}

	:global(.dark) .config-section {
		border-color: rgb(var(--color-surface-600));
	}

	button:disabled {
		cursor: default;
	}
</style>
