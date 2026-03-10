-- When referring to other pages in markdown we use relative file paths. When converting to HTML,
-- the extensions of those files must be changed from ".md" to ".html". To keep navigation smooth,
-- we'll add the "_self" attribute so that these links aren't opened in a new tab (the default
-- behaviour for links as defined in the template).

function Link(link)
	if link.target:match("%.md$") then
		link.target = link.target:gsub("%.md$", ".html")
		link.attributes["target"] = "_self"
		return link
	end
end
