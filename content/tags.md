{{ define "main" }}
      {{ if .Site.Taxonomies.tags }}
        <p>
          {{ "Maybe these tags will help you find what you're looking for. :smile:" | markdownify | emojify }}
        </p>
        <h2>Tags</h2>
        <div class="terms">
          <ul class="terms__list">
            {{ range .Site.Taxonomies.tags }}
              <li class="terms__term">
                <a href="{{ .Page.Permalink }}">#{{ .Page.Title }}</a
                ><span class="terms__term-count">{{ .Count }}</span>
              </li>
            {{ end }}
          </ul>
        </div>
      {{ end }}
    </div>
  </div>
{{ end }}
