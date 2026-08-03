<script lang="ts">
	import { onMount } from 'svelte';

	interface Props {
		param: string;
		type?: 'string' | 'int' | 'path' | 'number';
		description: string;
		default?: any;
		required?: boolean;
		compact?: boolean;
		value: any;
		onchange: (value: any) => void;
	}

	let {
		param,
		type = 'string',
		description,
		default: defaultValue = null,
		required = false,
		compact = false,
		value,
		onchange
	}: Props = $props();

	// Extract display name from param (e.g., "prodigal.threads" → "threads")
	let displayName = $derived(param.split('.').pop() || param);
	let isDefault = $derived(value === null || value === undefined || value === '');
	let displayValue = $derived(isDefault ? (defaultValue ?? '') : value);

	function handleInput(event: Event) {
		const target = event.target as HTMLInputElement;
		let newValue: any = target.value;

		// Convert to appropriate type
		if (type === 'int' || type === 'number') {
			newValue = newValue === '' ? null : parseInt(newValue, 10);
		}

		value = newValue;
		onchange(newValue);
	}
</script>

<div class="config-field {compact ? 'config-field-compact mb-2' : 'mb-4'}">
	<div class="flex-1 {compact ? 'mb-1' : 'mb-2'}">
		<span class="font-semibold text-surface-800 dark:text-surface-100">
			{displayName}
			{#if required}
				<span class="text-error-500">*</span>
			{/if}
		</span>
		<p class="text-xs text-surface-700 dark:text-surface-300 mt-1 leading-snug">{description}</p>
		{#if !isDefault && defaultValue !== null}
			<p class="text-xs text-primary-700 dark:text-primary-300 mt-1 font-medium">
				Default: {defaultValue}
			</p>
		{/if}
	</div>

	<div>
		{#if type === 'int' || type === 'number'}
			<input
				type="number"
				class="input w-full bg-white dark:bg-surface-900 border border-surface-300 dark:border-surface-600"
				placeholder={defaultValue !== null ? String(defaultValue) : ''}
				value={displayValue}
				oninput={handleInput}
				required={required}
				aria-label={displayName}
			/>
		{:else}
			<input
				type="text"
				class="input w-full bg-white dark:bg-surface-900 border border-surface-300 dark:border-surface-600"
				placeholder={defaultValue !== null ? String(defaultValue) : ''}
				value={displayValue}
				oninput={handleInput}
				required={required}
				aria-label={displayName}
			/>
		{/if}
	</div>
</div>

<style>
	.config-field {
		border: 1px solid rgb(var(--color-surface-300) / 0.85);
		border-radius: 0.75rem;
		padding: 0.875rem 1rem;
		background: rgb(var(--color-surface-50) / 0.85);
		gap: 0.75rem;
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(16rem, 24rem);
		align-items: start;
	}

	.config-field-compact {
		padding: 0.75rem 0.875rem;
		grid-template-columns: minmax(0, 1fr) minmax(12rem, 18rem);
	}

	:global(.dark) .config-field {
		border-color: rgb(var(--color-surface-700) / 0.9);
		background: rgb(var(--color-surface-900) / 0.65);
	}

	@media (max-width: 768px) {
		.config-field,
		.config-field-compact {
			grid-template-columns: 1fr;
		}
	}
</style>
