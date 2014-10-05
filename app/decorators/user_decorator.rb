class UserDecorator < ApplicationDecorator
  include AvatarHelper

  def link
    wrap_with_link(username || temporary_username || 'anonymous')
  end

  def img_link
    wrap_with_link(avatar_image_tag)
  end

  def full_name
    if model.name.present?
      "#{model.name} (#{model.username})"
    else
      model.username
    end
  end

  def joined_at
    created_at.strftime("%b %-d, %Y")
  end

  def theme
    model.theme || Theme.default
  end

  private

  def wrap_with_link(html)
    if username
      h.link_to html, h.profile_path(model), title: username
    else
      html
    end
  end

end
