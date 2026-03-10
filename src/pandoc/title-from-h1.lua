-- If the page title was not explicitly set, set it to the first heading. Header is run for each
-- header as the document is traversed. Headers fall under the Blocks category, so they are
-- traversed before Meta according to https://pandoc.org/lua-filters.html#typewise-traversal.
-- Therefore, this filter captures the first heading if one exists and uses it for the page title if
-- the page title was not explicitly set.

local title

function Header(header)
	if title then -- first heading already found
		return
	end

	title = pandoc.utils.stringify(header)
end

function Meta(meta)
	if meta.pagetitle or meta.title then -- title already set
		return
	end

	if not title or title == "" then -- no heading was found
		return
	end

	meta.pagetitle = title
	return meta
end
