########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2015 - 2025, EnterpriseDB Corporation
#
##########################################################################


"""Implement the Base class for RestClient"""

from abc import ABCMeta, abstractmethod
import six

from .registry import ClientRegistry


@six.add_metaclass(ClientRegistry)
class BaseRestClient(object):
    """
    class BaseRestClient(object):

    This is a base class for different rest client.
    Inherit this class to implement different type of remote server rest client
    implementation.

    Abstract Methods:
    -------- -------
    * server_manager(*args, **kwargs)
    - It should return a RemoteServerManager class object.

    * release_server(*args, **kwargs)
    - Implement the token release logic.

    * delete_server(*args, **kwargs)
    - Implement delete server from clients' pool.

    * refresh()
    - Implement this function to renew tokens in the session,
      which are about to expire.
    """

    @abstractmethod
    def server_manager(self, *args, **kwargs):
        pass

    @abstractmethod
    def release_server(self, *args, **kwargs):
        pass

    @abstractmethod
    def delete_server(self, *args, **kwargs):
        pass

    @abstractmethod
    def refresh(self):
        pass


@six.add_metaclass(ABCMeta)
class BaseAuthentication(object):
    """
    class BaseAuthentication(object)

        It is a base class for authentication.

    Abstract Methods:
    -------- -------
    * authenticate(**kwargs)
      - Implement this method to authenticate user and obtain token for further
        REST API calls

    * refresh_token()
      - Implement this method to regenerate new token if existing token is
        expired or near to expire.

    * release_token()
      - Implement this method to release valid token.
    """

    @abstractmethod
    def authenticate(self, *args, **kwargs):
        pass

    @abstractmethod
    def refresh_token(self, *args, **kwargs):
        pass

    @abstractmethod
    def release_token(self, *args, **kwargs):
        pass


@six.add_metaclass(ABCMeta)
class BaseRestSession:
    """
    This is the base class for REST Session
    """
    @abstractmethod
    def get(self, *args, **kwargs):
        pass

    @abstractmethod
    def post(self, *args, **kwargs):
        pass

    @abstractmethod
    def put(self, *args, **kwargs):
        pass

    @abstractmethod
    def delete(self, *args, **kwargs):
        pass

    @abstractmethod
    def patch(self, *args, **kwargs):
        pass

    def get_default_headers(self):
        return {"Content-Type": "application/json"}


@six.add_metaclass(ABCMeta)
class BaseRestResponse:
    """
    This is the base class for REST call response
    """

    @property
    @abstractmethod
    def exception(self):
        pass

    @property
    @abstractmethod
    def headers(self):
        pass

    @property
    @abstractmethod
    def status(self):
        pass

    @property
    @abstractmethod
    def text(self):
        pass

    @property
    @abstractmethod
    def content(self):
        pass

    @property
    @abstractmethod
    def iter_content(self):
        pass
