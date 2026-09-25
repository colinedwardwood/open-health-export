The accessibility-size UI audits now run at the largest accessibility text size;
they had been passing an invalid content-size name and auditing the default
size. A canary fails if the size is not applied (#39).
