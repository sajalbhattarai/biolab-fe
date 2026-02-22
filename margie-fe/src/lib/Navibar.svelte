<script lang="ts">
  import { goto, afterNavigate } from '$app/navigation';
  import { Calendar, CircleUser, LogOut, Menu, X } from 'lucide-svelte';
  import { AppBar } from '@skeletonlabs/skeleton-svelte';
  import { isLoggedIn, clearToken } from '$lib/auth.js';

  let drawerOpen = $state(false);
  let loggedIn = $state(false);

  // Re-check on every navigation (including the redirect after login).
  // afterNavigate also fires on first mount, replacing the need for onMount.
  afterNavigate(() => {
    loggedIn = isLoggedIn();
  });

  function toggleDrawer() {
    drawerOpen = !drawerOpen;
  }

  function closeDrawer() {
    drawerOpen = false;
  }

  function logout() {
    clearToken();
    goto('/login');
  }
</script>

<AppBar>
  	<AppBar.Toolbar class="grid-cols-[auto_1fr_auto]">
		<AppBar.Lead>
			<button type="button" class="btn-icon btn-icon-lg hover:preset-tonal" on:click={toggleDrawer}>
				<Menu />
			</button>
		</AppBar.Lead>
		<AppBar.Headline>
			<a href="/" class="text-2xl font-bold hover:text-primary-600 transition-colors cursor-pointer">Bioinformatics Supercomputing Platform</a>
		</AppBar.Headline>
		<AppBar.Trail>
			{#if loggedIn}
				<a href="/profile/" class="btn-icon hover:preset-tonal" title="Profile"><CircleUser class="size-6" /></a>
				<button type="button" class="btn-icon hover:preset-tonal" title="Sign out" on:click={logout}>
					<LogOut class="size-5" />
				</button>
			{:else}
				<a href="/login" class="btn variant-outline-primary text-sm px-4 py-1">Sign in</a>
			{/if}
		</AppBar.Trail>
	</AppBar.Toolbar>
</AppBar>

<!-- Backdrop -->
{#if drawerOpen}
	<div
		class="fixed inset-0 bg-black/50 z-40 transition-opacity"
		on:click={closeDrawer}
		role="button"
		tabindex="0"
		on:keydown={(e) => e.key === 'Escape' && closeDrawer()}
	></div>
{/if}

<!-- Drawer -->
<div
	class="fixed top-0 left-0 h-full w-64 bg-surface-100 dark:bg-surface-800 shadow-xl z-50 transform transition-transform duration-300 {drawerOpen ? 'translate-x-0' : '-translate-x-full'}"
>
	<div class="p-4 space-y-4">
		<div class="flex items-center justify-between mb-6">
			<h2 class="text-2xl font-bold">Menu</h2>
			<button type="button" class="btn-icon hover:preset-tonal" on:click={closeDrawer}>
				<X />
			</button>
		</div>

		<nav class="space-y-2">
			<a href="/" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Home</p>
			</a>
			<a href="/analyze" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Analyze</p>
			</a>
			<a href="/filesearch" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">File Search</p>
			</a>
			<a href="/run_script" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Run Slurm</p>
			</a>
			<a href="/run_ssh" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Run SSH</p>
			</a>

			<div class="border-t border-surface-300 dark:border-surface-600 my-2"></div>

			<a href="/results/mock" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Results (Mock)</p>
			</a>
			<a href="/results/historical" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Results (Historical)</p>
			</a>

			<div class="border-t border-surface-300 dark:border-surface-600 my-2"></div>

			<a href="/roadmap" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Roadmap</p>
			</a>
			<a href="/methods" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Methods</p>
			</a>
			<!-- <a href="/contributors" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Contributors</p>
			</a> -->
			<a href="/dane" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Dane</p>
			</a>
			<a href="/profile" class="block p-4 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" on:click={closeDrawer}>
				<p class="text-lg font-semibold">Profile</p>
			</a>
		</nav>
	</div>
</div>
