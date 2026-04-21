/**
 * SearXNG Web Search Extension
 *
 * Provides web_search and web_fetch tools to the LLM via a self-hosted
 * SearXNG instance. The LLM can search the web and fetch page content.
 *
 * Configuration:
 *   SEARXNG_URL - Base URL of the SearXNG instance (default: https://searxng.internal.crussell.io)
 *
 * Tools:
 *   web_search - Search the web and return results
 *   web_fetch  - Fetch and extract text content from a URL
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { StringEnum } from "@mariozechner/pi-ai";

const SEARXNG_URL = process.env.SEARXNG_URL ?? "https://searxng.internal.crussell.io";

interface SearXNGResult {
	title?: string;
	url?: string;
	content?: string;
	engine?: string;
	score?: number;
	category?: string;
	publishedDate?: string;
}

interface SearXNGResponse {
	query?: string;
	number_of_results?: number;
	results?: SearXNGResult[];
	unresponsive_engines?: string[];
	suggestions?: string[];
	infoboxes?: Array<{
		content?: string;
		infobox?: string;
		urls?: Array<{ url?: string; title?: string }>;
	}>;
}

async function searchSearXNG(
	query: string,
	options: {
		categories?: string;
		time_range?: string;
		page?: number;
	},
	signal?: AbortSignal,
): Promise<SearXNGResponse> {
	const params = new URLSearchParams({
		q: query,
		format: "json",
	});

	if (options.categories) params.set("categories", options.categories);
	if (options.time_range) params.set("time_range", options.time_range);
	if (options.page && options.page > 1) params.set("pageno", String(options.page));

	const url = `${SEARXNG_URL}/search?${params.toString()}`;

	const response = await fetch(url, {
		signal,
		headers: {
			Accept: "application/json",
		},
	});

	if (!response.ok) {
		throw new Error(`SearXNG returned ${response.status}: ${response.statusText}`);
	}

	return (await response.json()) as SearXNGResponse;
}

function formatResults(data: SearXNGResponse, maxResults = 10): string {
	const lines: string[] = [];

	if (data.suggestions && data.suggestions.length > 0) {
		lines.push(`Suggestions: ${data.suggestions.join(", ")}`);
		lines.push("");
	}

	if (data.infoboxes && data.infoboxes.length > 0) {
		for (const box of data.infoboxes.slice(0, 2)) {
			if (box.infobox) lines.push(`ℹ️  ${box.infobox}`);
			if (box.content) lines.push(box.content.slice(0, 500));
			lines.push("");
		}
	}

	const results = data.results?.slice(0, maxResults) ?? [];
	if (results.length === 0) {
		return "No results found.";
	}

	lines.push(`Found ${data.number_of_results ?? results.length} results (showing top ${results.length}):`);
	lines.push("");

	for (let i = 0; i < results.length; i++) {
		const r = results[i];
		const num = i + 1;
		const title = r.title ?? "Untitled";
		const url = r.url ?? "";
		const snippet = r.content ?? "";
		const date = r.publishedDate ? ` (${r.publishedDate.split("T")[0]})` : "";

		lines.push(`${num}. ${title}${date}`);
		if (url) lines.push(`   ${url}`);
		if (snippet) lines.push(`   ${snippet.slice(0, 300)}`);
		lines.push("");
	}

	return lines.join("\n");
}

async function fetchPage(url: string, signal?: AbortSignal): Promise<string> {
	const response = await fetch(url, {
		signal,
		headers: {
			Accept: "text/html,text/plain,application/json",
			"User-Agent":
				"Mozilla/5.0 (compatible; PiAgent/1.0; +https://github.com/pi-coding-agent)",
		},
	});

	if (!response.ok) {
		throw new Error(`Fetch failed: ${response.status} ${response.statusText}`);
	}

	const contentType = response.headers.get("content-type") ?? "";
	const body = await response.text();

	// If JSON, pretty print it
	if (contentType.includes("application/json")) {
		try {
			const parsed = JSON.parse(body);
			return JSON.stringify(parsed, null, 2).slice(0, 50_000);
		} catch {
			return body.slice(0, 50_000);
		}
	}

	// If plain text, return as-is
	if (contentType.includes("text/plain")) {
		return body.slice(0, 50_000);
	}

	// For HTML, strip tags to get readable text
	if (contentType.includes("text/html") || body.trimStart().startsWith("<")) {
		return stripHtml(body);
	}

	return body.slice(0, 50_000);
}

function stripHtml(html: string): string {
	let text = html;

	// Remove script and style blocks entirely
	text = text.replace(/<script[\s\S]*?<\/script>/gi, "");
	text = text.replace(/<style[\s\S]*?<\/style>/gi, "");
	text = text.replace(/<nav[\s\S]*?<\/nav>/gi, "");
	text = text.replace(/<footer[\s\S]*?<\/footer>/gi, "");
	text = text.replace(/<header[\s\S]*?<\/header>/gi, "");

	// Convert common block elements to newlines
	text = text.replace(/<\/?(p|div|br|h[1-6]|li|tr|hr)[^>]*>/gi, "\n");

	// Remove all remaining HTML tags
	text = text.replace(/<[^>]+>/g, "");

	// Decode common HTML entities
	text = text
		.replace(/&amp;/g, "&")
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&quot;/g, '"')
		.replace(/&#39;/g, "'")
		.replace(/&nbsp;/g, " ");

	// Collapse whitespace
	text = text.replace(/[ \t]+/g, " ");
	text = text.replace(/\n{3,}/g, "\n\n");

	return text.trim().slice(0, 50_000);
}

export default function searxngSearchExtension(pi: ExtensionAPI) {
	// ── web_search tool ─────────────────────────────────────────────────
	pi.registerTool({
		name: "web_search",
		label: "Web Search",
		description:
			"Search the web using SearXNG. Returns a list of results with titles, URLs, and snippets. " +
			"Use this when you need to find information online, look up documentation, check current events, " +
			"or research topics. Supports search operators like site:github.com, filetype:pdf, etc.",
		promptSnippet: "Search the web via SearXNG for real-time information, documentation, and answers",
		promptGuidelines: [
			"Prefer web_search over guessing when the user asks about current events, recent changes, or specific facts you're unsure about.",
			"Use web_fetch to read the full content of promising search results.",
			"For time-sensitive queries, use the time_range parameter (day, month, year).",
		],
		parameters: Type.Object({
			query: Type.String({
				description:
					"The search query. Supports search engine syntax like site:, filetype:, intitle:, etc.",
			}),
			categories: Type.Optional(
				StringEnum(["general", "news", "images", "videos", "science", "it", "files", "music"] as const, {
					description: "Search category to focus results (default: general)",
				}),
			),
			time_range: Type.Optional(
				StringEnum(["day", "month", "year"] as const, {
					description: "Restrict results to a time range",
				}),
			),
			page: Type.Optional(
				Type.Number({
					description: "Page number for pagination (default: 1)",
					minimum: 1,
				}),
			),
		}),
		async execute(_toolCallId, params, signal) {
			try {
				const data = await searchSearXNG(params.query, {
					categories: params.categories,
					time_range: params.time_range,
					page: params.page,
				}, signal);

				const formatted = formatResults(data);

				return {
					content: [{ type: "text", text: formatted }],
					details: {
						query: params.query,
						resultCount: data.results?.length ?? 0,
						totalResults: data.number_of_results,
					},
				};
			} catch (err) {
				const message = err instanceof Error ? err.message : String(err);
				return {
					content: [
						{
							type: "text",
							text: `Search failed: ${message}. The SearXNG instance at ${SEARXNG_URL} may be unreachable.`,
						},
					],
					isError: true,
					details: { error: message },
				};
			}
		},
	});

	// ── web_fetch tool ──────────────────────────────────────────────────
	pi.registerTool({
		name: "web_fetch",
		label: "Web Fetch",
		description:
			"Fetch the content of a web page and extract its text. Use this to read the full content " +
			"of URLs found via web_search, or any URL the user provides. Handles HTML (strips tags), " +
			"plain text, and JSON responses.",
		promptSnippet: "Fetch and read the text content of any web page URL",
		promptGuidelines: [
			"Use web_fetch to read the full content of URLs found in search results.",
			"Results are truncated to ~50KB of text. For very long pages, the content may be cut off.",
		],
		parameters: Type.Object({
			url: Type.String({
				description: "The URL to fetch",
			}),
		}),
		async execute(_toolCallId, params, signal) {
			try {
				const content = await fetchPage(params.url, signal);

				return {
					content: [{ type: "text", text: content }],
					details: {
						url: params.url,
						length: content.length,
					},
				};
			} catch (err) {
				const message = err instanceof Error ? err.message : String(err);
				return {
					content: [
						{
							type: "text",
							text: `Failed to fetch ${params.url}: ${message}`,
						},
					],
					isError: true,
					details: { error: message, url: params.url },
				};
			}
		},
	});
}
