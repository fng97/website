-- When referring to other pages in markdown we use relative file paths. When converting to HTML,
-- the extensions of those files must be changed from ".md" to ".html".

function Link(link)
	local is_external = link.target:sub(1, 8) == "https://" or link.target:sub(1, 7) == "http://"
	local is_mailto = link.target:sub(1, 7) == "mailto:"

	if not is_external and not is_mailto then
		link.target = link.target:gsub("%.md$", ".html")
	end

	return link
end
