///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

import React, { useEffect } from 'react';

import clsx from 'clsx';
import PropTypes from 'prop-types';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import ChevronRightIcon from '@mui/icons-material/ChevronRight';
import InfoRoundedIcon from '@mui/icons-material/InfoRounded';
import CircularProgress from '@mui/material/CircularProgress';
import Tooltip from '@mui/material/Tooltip';
import Radio from '@mui/material/Radio';

import gettext from 'sources/gettext';
import { PgTreeSelectionContext } from 'sources/PgTreeView';
import {
  NodeCheckBox,
  NodeCheckBoxIcon,
  NodeIndeterminateCheckBoxIcon,
  FocusedNode,
  Node,
  ErrNode,
  CollectionArrowSpan,
  InfoIconButton,
} from './styles';

function TreeNode({
  node, style, tree, hasCheckbox, onNodeSelectionChange,
  handleToggle, selectionOnClick, onChecked=null }) {
  const pgTreeSelCtx = React.useContext(PgTreeSelectionContext);
  const [isSelected, setIsSelected] = React.useState(
    pgTreeSelCtx.includes(node.id) || node.data?.isSelected
  );
  const [isIndeterminate, setIsIndeterminate] = React.useState(
    node?.parent.level === 0);

  useEffect(() => {
    setIsIndeterminate(node.data.isIndeterminate);
  }, [node?.data?.isIndeterminate]);

  useEffect(() => {
    if (isSelected) {
      if (!pgTreeSelCtx.includes(node.id)) {
        node.selectMulti();
        onNodeSelectionChange();
      }
    }
  }, [isSelected]);
  useEffect(()=>{
    if(node.data.isOpen) node.open();
  }, []);

  const resetTreeData = (parentId=null) => {
    tree.selectedNodes.filter(n=>!(n.parent.id===parentId || n.id===parentId)).forEach(n=>{
      n.deselect();
      n.data.isSelected = false;
      n.data.isFocused = false;
      deselectAllChild(n);
      n.close();
    });
  };
  const onCheckboxSelection = (e) => {
    if (hasCheckbox) {
      setIsSelected(e.currentTarget.checked);
      node.data.isSelected = e.currentTarget.checked;
      if (e.currentTarget.checked) {
        if(node?.data?.radio){
          resetTreeData();
          tree.select(node.id);
          node.open();
        } else {
          if(node.parent?.data?.radio){
            resetTreeData(node.parent.id);
          }
          tree.selectMulti(node.id);
        }
        if (!node.isLeaf) {
          node.data.isIndeterminate = false;
          selectAllChild(node, tree, 'checkbox', pgTreeSelCtx);
        } else if (node?.parent) {
          checkAndSelectParent(node);
        }
        if (node?.level == 0) {
          node.data.isIndeterminate = false;
        }
        node.focus();
      } else {
        node.deselect(node);
        if (!node.isLeaf) {
          deselectAllChild(node);
        }
        if (node?.parent) {
          if (!node.parent.data?.radio) {
            node.parent.data.isIndeterminate = false;
            deselectParentNode(node.parent);
          } else {
            node.parent.select();
          }

        }
      }
    }
    if (onChecked) {
      onChecked(e, node);
    }
    tree.scrollTo(node.id, 'center');
    onNodeSelectionChange();
  };

  const onSelect = (e) => {
    node.focus();
    if (selectionOnClick && !node.isSelected && !node.data?.radio && node.isLeaf) {
      node.data.isSelected = true;
      node.data.isFocused = true;
      node.selectMulti();
      onNodeSelectionChange();
    }
    e.stopPropagation();
  };

  const onKeyDown = (e) => {
    if (e.code == 'Enter') {
      onSelect(e);
    }
  };

  const getErrIcon = () => {
    if (node?.data?.err_msg) {
      return (
        <ErrNode inode={node.data.inode}>
          <Tooltip title={gettext(node.data.err_msg)}>
            <InfoIconButton inode={node.data.inode} >
              <InfoRoundedIcon />
            </InfoIconButton>
          </Tooltip>
        </ErrNode>
      );
    }
    return <span className={clsx(node.data.icon)} />;
  };

  const getIcon = () => {
    if (node.data?.radio) {
      return (<Radio
        style={{ padding: 0 }}
        color="primary"
        isleafnode={Boolean(!node?.data?.isInternal).toString()}
        checked={isSelected}
        onChange={onCheckboxSelection} />);
    }
    return (<NodeCheckBox
      style={{ padding: 0 }}
      color="primary"
      isleafnode={Boolean(!node?.data?.isInternal).toString()}
      checked={isSelected}
      checkedIcon={
        isIndeterminate ?
          <NodeIndeterminateCheckBoxIcon /> :
          <NodeCheckBoxIcon />}
      onChange={onCheckboxSelection} />);
  };
  return (
    <FocusedNode
      style={style}
      isfocused={Boolean(node?.isFocused || node?.data?.isFocused).toString()}
      iserrnode={(Boolean(node?.data?.err_msg)).toString()}
      onClick={onSelect} onKeyDown={onKeyDown} selectionOnClick>
      <CollectionArrow
        node={node} tree={tree}
        selectedNodeIds={pgTreeSelCtx} handleToggle={handleToggle}
      />
      {
        hasCheckbox && (
          !('checkbox' in node.data) || node?.data?.checkbox) ? getIcon() :
          getErrIcon()
      }
      <Node isicon={(Boolean(node?.data?.icon)).toString()}
        iserrmsg={(Boolean(node?.data?.err_msg)).toString()}
        className={clsx(node?.data?.icon)}>{node?.data?.name}</Node>
    </FocusedNode>
  );
}

TreeNode.propTypes = {
  node: PropTypes.object,
  style: PropTypes.any,
  tree: PropTypes.object,
  hasCheckbox: PropTypes.bool,
  onNodeSelectionChange: PropTypes.func,
  handleToggle: PropTypes.func,
  selectionOnClick: PropTypes.bool,
  selectionType: PropTypes.string,
  onChecked: PropTypes.func,
};

function selectAllChild(chNode, tree, source, selectedNodeIds) {
  let selectedChild = 0;
  chNode?.children?.filter(c=>c.data.checkbox).forEach((child) => {
    if (!child.isLeaf) {
      child.data.isIndeterminate = false;
    }
    if (
      ((source == 'expand' && selectedNodeIds.includes(child.id)) ||
      source == 'checkbox')
    ) {
      child.data.isSelected = true;
      selectedChild += 1;
    }
    child.selectMulti(child.id);

    if (child?.children) {
      selectAllChild(child, tree, source, selectedNodeIds);
    }
  });

  if (selectedChild < chNode?.children.length) {
    chNode.data.isIndeterminate = true;
  } else {
    chNode.data.isIndeterminate = false;
  }

  if (chNode?.parent) {
    checkAndSelectParent(chNode);
  }
}

function checkAndSelectParent(chNode) {
  let isAllChildSelected = true;
  chNode?.parent?.children?.forEach((child) => {
    if (!child.isSelected) {
      isAllChildSelected = false;
    }
  });
  if (chNode?.parent) {
    if (isAllChildSelected) {
      if (chNode.parent?.level == 0) {
        chNode.parent.data.isIndeterminate = true;
      } else {
        chNode.parent.data.isIndeterminate = false;
      }
      chNode.parent.selectMulti(chNode.parent.id);
    } else {
      chNode.parent.data.isIndeterminate = true;
      chNode.parent.selectMulti(chNode.parent.id);
    }
    chNode.parent.data.isSelected = true;
    checkAndSelectParent(chNode.parent);
  }
}

checkAndSelectParent.propTypes = {
  chNode: PropTypes.object,
};

function deselectAllChild(chNode) {
  chNode?.children?.forEach(child => {
    child.deselect(child);
    child.data.isSelected = false;
    if (child?.children) {
      deselectAllChild(child);
    }
  });
}

function deselectParentNode(chNode) {
  if (chNode) {
    let isAnyChildSelected = false;
    chNode.children.forEach((childNode) => {
      if (childNode.isSelected && !isAnyChildSelected) {
        isAnyChildSelected = true;
      }
    });
    if (isAnyChildSelected) {
      chNode.data.isSelected = true;
      chNode.data.isIndeterminate = true;
    } else {
      chNode.deselect(chNode);
      chNode.data.isSelected = false;
    }
  }

  if (chNode?.parent) {
    deselectParentNode(chNode.parent);
  }
}

function CollectionArrow({
  node,
  tree,
  selectedNodeIds,
  handleToggle = false,
}) {
  const [loading, setLoading] = React.useState(false);

  const toggleNode = (e) => {
    e.stopPropagation(true);
    e.preventDefault();
    if (node.data.isInternal) {
      if (!node.isOpen) {
        setLoading(true);
        if (handleToggle) {
          handleToggle(node.id);
        }
        node.toggle();
        setTimeout(() => {
          !node.isOpen && node.open();
          if (node.isSelected) {
            node.data.isSelected = true;
            selectAllChild(
              node, tree, 'expand',
              selectedNodeIds
            );
          }
          setLoading(false);
        }, 100);
      } else {
        node.close();
      }
    }
  };
  return (
    <CollectionArrowSpan
      haschildren={Boolean(
        (node.data?.isInternal &&
          (node?.children?.length > 0 || node?.data?.inode)) ||
          (!node.data?.isInternal && !node?.children)
      ).toString()}
      onClick={toggleNode}
    >
      {node.data?.isInternal &&
      (node?.children?.length > 0 || node?.data?.inode) ? (
          <ToggleArrowIcon node={node} loading={loading} />
        ) : null}
    </CollectionArrowSpan>
  );
}

CollectionArrow.propTypes = {
  node: PropTypes.object,
  tree: PropTypes.object,
  selectedNodeIds: PropTypes.array,
  handleToggle: PropTypes.func,
};

function ToggleArrowIcon({ node, loading }) {
  return loading ? (
    <CircularProgress size={16} thickness={4} />
  ) : node.isOpen ? (
    <ExpandMoreIcon />
  ) : (
    <ChevronRightIcon />
  );
}

ToggleArrowIcon.propTypes = {
  node: PropTypes.object,
  loading: PropTypes.bool,
};

export default TreeNode;
