---
layout: post
title: Taming mailing lists with NeoMutt and notmuch
tags: general productivity
---

Still, a lot of Free and Open Source Software(FOSS) projects use mailing lists
as the primary form of communication and more importantly: sending patches.
As my new job required following certain Linux mailing lists, it all seemed very new
as I never had a mailing list-based workflow before. The key differentiator in a mailing
list-based workflow is that there is going to be a huge influx of emails but not all of them
are relevant to you. So the challenge that many people face when they start is filtering emails. Letting
all emails go to the inbox and then filtering them manually is an arduous task that will soon prove to
be futile.

In this article, I will try to cover some tips and tricks to handle mailing lists and
make it as usable as a part of the daily workflow.

I use Gmail to subscribe to mailing lists and it was almost impossible to
follow things via the web-based Gmail client. I even tried setting up filters
but it still didn't feel "right" to me. After trying multiple clients such as
Thunderbird, and talking to people, I finally found the one: [NeoMutt](https://neomutt.org/) +
[notmuch](https://notmuchmail.org/) based on my colleague's suggestion.
Initially, it felt like a daunting task to set it up but the final result gave me
that peace of mind that I am never planning to look back. I hope explaining my workflow
can help others and make parsing through the mailing list a bit less scary.

NeoMutt is a command-line mail reader (and a fork of Mutt) and notmuch is an
awesome Mail Indexer. Mbsync(iSync) will be used as a way to synchronize mails
with the mail server through IMAP. As mbsync downloads the email locally, it is 
very useful for offline viewing. We will not go over mbsync setup here but there
is a good ArchWiki [page](https://wiki.archlinux.org/title/isync). As a prerequisite,
make sure the mails are synced using mbsync locally to a folder in MailDir format.

The basic idea is to filter and tag the incoming emails with notmuch and use Neomutt's inbuilt
notmuch integration to view the emails on a per tag basis.

## Notmuch
Notmuch allows to compose logical rules to add tags to an email. My notmuch configuration
is very basic and it is as follows:
```
[database]
path=<path-to-maildir>

[user]
name=<name>
primary_email=<email>

[new]
tags=unread;

[search]
exclude_tags=spam;

[maildir]
synchronize_flags=true

```
Once this is wired, tags can be applied to the emails based on our custom rules.

My strategy is to **apply a unique tag per mailing list**. But there could
be cases where there is a single mailing list for different topics. I will also show
a technique where we can add some filters to only extract relevant emails from that
mailing list.

### Syncing script
An easy way to manage and apply tags with notmuch is to create a custom script
that can run every time we want to download emails locally. The script will run
`mbsync` to synchronize emails and run notmuch to apply tags on them.

Syncing script example:

```
#!/bin/sh

/usr/bin/mbsync <mbsync-group>

notmuch new

#Example tagging for the linux block layer mailing list
notmuch tag +block -- cc:linux-block@vger.kernel.org or to:linux-block@vger.kernel.org
notmuch tag +io_uring -- cc:io-uring@vger.kernel.org or to:io-uring@vger.kernel.org
```
Syncing script also allows us to mark some unwanted mails to be
marked as read. I follow the development of `NVMe` emulation in QEMU but there is a single
mailing list in QEMU for the whole block layer. `notmuch` has tagging also based on 
`Subject`. As I know the email that is of my interest has the `hw/nvme` in the `Subject` line,
I do the following in my syncing script to only extract the relevant emails:

```
notmuch tag +qemu-nvme -- cc:qemu-block@nongnu.org or to:qemu-block@nongnu.org and subject:"hw/nvme"

# I am not interested in anything that is not related to hw/nvme
notmuch tag -unread -- cc:qemu-block@nongnu.org or to:qemu-block@nongnu.org not tag:qemu-nvme
```

The mails coming from `qemu-block@nongnu.org` and do not contain
the `subject:hw/nvme` are automatically marked as `read`. As the reader might notice, this is a very useful feature to declutter
the Mailbox from unwanted emails.

### Github notifications
This technique can also be extended to following PRs for projects that are hosted on Github.
Once the [notification via email](https://docs.github.com/en/account-and-profile/managing-subscriptions-and-notifications-on-github/setting-up-notifications/configuring-notifications#customizing-your-email-notifications)
is enabled for PRs in Github, a custom notmuch tag can be applied on the `Subject` to filter out PRs that are not interesting.

For example, to follow only the developments in the `Kernel` in [SerenityOS](https://github.com/SerenityOS/serenity),
the following rule can be added:
```
notmuch tag +serenity-kernel -- to:serenity@noreply.github.com and subject:"Kernel"
notmuch tag +serenity -- tag:personal and to:serenity@noreply.github.com        
                                                                                
# I am not interested in anything that is not related to Kernel and not directed to me
notmuch tag -unread -- to:serenity@noreply.github.com and not tag:serenity-kernel and not tag:serenity
```
Of course, the project that is being followed should have some sort of a contributing guideline
that enforces the subsystem to be mentioned in the `Subject` or the `Body`.


## Neomutt + Notmuch integration
Neomutt has this concept of `virtual-mailboxes` that takes description or a `notmuch URL` as its
input. Neomutt has a custom syntax for notmuch search arguments which is used to construct
the `notmuch URL`.

Ideally, it is better to create a **virtual mailbox** per notmuch tag in neomutt.

This is my configuration for the virtual-mailbox which goes in `neomutt` config:
```
#neomuttrc

virtual-mailboxes "block" "notmuch://?query=tag:block%20and%20tag:unread"
virtual-mailboxes "io_uring" "notmuch://?query=tag:io_uring%20and%20tag:unread"
```
The "block" virtual-mailbox will show only **new** mails that come from the
linux-block mailing list (the same applies to "io_uring" virtual-mailbox).
I prefer to only see the new emails from the respective mailing list instead
of seeing it along with the old emails from that mailing list.

### Pruning and Reading
Not all emails in a mailing list might be of importance so my workflow involves
a pruning step where I get rid of uninteresting patches and I mark patches that I want
to revisit later with a `todo` tag. Neomutt allows to easily tag a mail with a shortcut as follows:
```
macro index,pager tt "<modify-labels>!todo\n" "Toggle the 'todo' tag"
```
The above macro binds `tt` with toggling the `todo` tag on an email.

So while pruning the mails, I tag the important emails with a `todo` tag so that I can
go through them later.
The virtual-mailbox configuration with `todo` tag is as follows:
```
virtual-mailboxes "todo" "notmuch://?query=tag:todo"
virtual-mailboxes "block" "notmuch://?query=tag:block%20and%20tag:unread%20and%20not%20tag:todo"
virtual-mailboxes "io_uring" "notmuch://?query=tag:io_uring%20and%20tag:unread%20and%20not%20tag:todo"
```
The above virtual-mailbox rule allows ignoring emails with `todo` label that are there in the `block` and `io_uring`
virtual-mailbox. This is useful while pruning the mailing list as I don't want to see the email with `todo` tag even
if it is unread.

*TIP*: Add a macro that calls the syncing script from NeoMutt. I have configured `S` to run the syncing script:
```
macro index S "<shell-escape><path-to-syncing-script> 2>&1<enter>" "sync email and notmuch"
```

*TIP*: Github sends the link of the patch/diff file in the email. A simple macro can be added
to download the diff file locally as follows:
```
bind index,pager O noop
macro index,pager O "| grep \"\^https\.\*diff\$\" | xargs wget "
```

## Conclusion
That is it for this article. I will try to keep this article up-to-date as I learn new
tricks to optimize my workflow.

This setup avoids the need to go to the main `Inbox` folder and rather directly
jump into the mails with relevant tags. Personally, this setup creates less cognitive overhead and less context switching because the 
relevant emails are filtered and organized. 

| ![Setup\label{classdiag}](/assets/mailinglist/neomutt.png) |
|:--:|
| *My neomutt + notmuch setup* |


Useful articles:
- [Creating a local email setup with mbsync + msmtp + neomutt + notmuch.](https://blog.flaport.net/configuring-neomutt-for-email.html)
- [Patch Workflow With Mutt - 2019](http://kroah.com/log/blog/2019/08/14/patch-workflow-with-mutt-2019/)

Hope you enjoyed the article and found it helpful. Happy mailing!
