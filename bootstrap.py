"""Idempotent first-boot setup, run through `pretix shell` after migrate and before the web server starts.

Replaces the superuser admin@localhost / admin that migration 0001 creates, then makes an organizer with an administrators team
and an API token, so an agent can use /api/v1 straight away. Every value comes from the environment; running it again changes
nothing but resets the password and token to the configured ones.
"""
import os

from django.db import transaction

from pretix.base.models import Organizer, Team, TeamAPIToken, User

email = os.environ["ADMIN_EMAIL"].strip().lower()
password = os.environ["ADMIN_PASSWORD"]
token = os.environ["ADMIN_API_KEY"]
slug = os.environ.get("ORGANIZER_SLUG", "main")

with transaction.atomic():
    user = User.objects.filter(email__iexact=email).first()
    default = User.objects.filter(email__iexact="admin@localhost").first()
    if user is None and default is not None:
        user = default
        user.email = email
    if user is None:
        user = User(email=email)
    user.is_staff = True
    user.is_active = True
    user.set_password(password)
    user.save()
    if default is not None and default.pk != user.pk:
        default.delete()

    organizer, _ = Organizer.objects.get_or_create(slug=slug, defaults={"name": "Main organizer"})
    team, _ = Team.objects.get_or_create(
        organizer=organizer,
        name="Administrators",
        defaults={
            "all_events": True,
            "all_event_permissions": True,
            "all_organizer_permissions": True,
        },
    )
    team.all_events = True
    team.all_event_permissions = True
    team.all_organizer_permissions = True
    team.save()
    team.members.add(user)

    api = TeamAPIToken.objects.filter(team=team, name="railway-agent").first()
    if api is None:
        api = TeamAPIToken(team=team, name="railway-agent")
    api.token = token
    api.active = True
    api.save()

print("[railway] administrator %s, organizer %s and API token are in place" % (email, slug))
